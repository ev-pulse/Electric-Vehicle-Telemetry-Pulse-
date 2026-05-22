import azure.functions as func
import logging
import os
import json
import hmac
import hashlib
import re
import requests
import sys

sys.path.insert(0, os.path.dirname(__file__))
from sql_query import execute_query, get_table_schema
from gpt_client import convert_to_sql, generate_answer

APP_ID = os.environ["MICROSOFT_APP_ID"]
APP_PASSWORD = os.environ["MICROSOFT_APP_PASSWORD"]
TENANT_ID = os.environ.get("MICROSOFT_TENANT_ID", "")
SLACK_BOT_TOKEN = os.environ.get("SLACK_BOT_TOKEN", "")
SLACK_SIGNING_SECRET = os.environ.get("SLACK_SIGNING_SECRET", "")

# Slack 중복 이벤트 방지용 event_id 캐시 (인스턴스 재시작 시 초기화됨)
_processed_event_ids: set = set()


def send_teams_reply(body, text):
    resp = requests.post(
        f"https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token",
        data={
            "grant_type": "client_credentials",
            "client_id": APP_ID,
            "client_secret": APP_PASSWORD,
            "scope": "https://api.botframework.com/.default",
        },
        timeout=10 # 10초안에 토큰 못 받아오면 타임아웃 처리
    )
    token = resp.json()["access_token"]

    url = f"{body['serviceUrl'].rstrip('/')}/v3/conversations/{body['conversation']['id']}/activities/{body['id']}"
    resp = requests.post(url, json={
        "type": "message", "text": text,
        "replyToId": body["id"],
        "from": body["recipient"], "recipient": body["from"],
        "conversation": body["conversation"]
    }, headers={"Authorization": f"Bearer {token}"}, timeout=10)

    if not resp.ok:
        logging.error("Teams Bot Connector 오류 %s: %s", resp.status_code, resp.text)

# Slack 요청의 유효성 검증
def verify_slack_signature(req: func.HttpRequest, raw_body: bytes) -> bool:
    timestamp = req.headers.get("X-Slack-Request-Timestamp", "")
    signature = req.headers.get("X-Slack-Signature", "")
    base = f"v0:{timestamp}:{raw_body.decode()}"
    expected = "v0=" + hmac.new(
        SLACK_SIGNING_SECRET.encode(), base.encode(), hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature)


def send_slack_reply(channel, text):
    resp = requests.post(
        "https://slack.com/api/chat.postMessage",
        json={"channel": channel, "text": text},
        headers={"Authorization": f"Bearer {SLACK_BOT_TOKEN}"},
        timeout=10
    )
    if not resp.ok or not resp.json().get("ok"):
        logging.error("Slack API 오류 %s: %s", resp.status_code, resp.text)


def handle_query(q):
    schema = get_table_schema()
    sql = convert_to_sql(q, schema)
    result = execute_query(sql)
    logging.info("SQL 결과: %s", result)
    return generate_answer(q, result)


def main(req: func.HttpRequest) -> func.HttpResponse:
    try:
        raw_body = req.get_body()
        body = json.loads(raw_body)
        msg_type = body.get("type")

        # --- Slack: URL 인증 챌린지 (앱함수 등록 시 1회) ---
        if msg_type == "url_verification":
            return func.HttpResponse(
                json.dumps({"challenge": body["challenge"]}),
                mimetype="application/json", status_code=200
            )

        # --- Slack: 앱 멘션 이벤트 ---
        if msg_type == "event_callback":
            if req.headers.get("X-Slack-Retry-Num"):
                logging.info("중복 요청 무시 (Slack retry): %s", req.headers.get("X-Slack-Retry-Num"))
                return func.HttpResponse(status_code=200)
            logging.info("원본 요청 수신: event_callback")
            if not verify_slack_signature(req, raw_body):
                logging.warning("Slack 서명 검증 실패")
                return func.HttpResponse("Unauthorized", status_code=401)
            event_id = body.get("event_id")
            if event_id:
                if event_id in _processed_event_ids:
                    logging.info("중복 요청 무시 (event_id): %s", event_id)
                    return func.HttpResponse(status_code=200)
                if len(_processed_event_ids) >= 100:
                    # set.pop()은 임의 요소 제거 — 순서 보장 불필요, 크기 제한이 목적
                    _processed_event_ids.pop()
                _processed_event_ids.add(event_id)
            event = body.get("event", {})
            if event.get("type") != "app_mention" or event.get("bot_id"):
                return func.HttpResponse(status_code=200)
            q = re.sub(r"<@[A-Z0-9]+>", "", event.get("text", "")).strip()
            channel = event.get("channel")
            send_slack_reply(channel, handle_query(q) if q else "질문을 입력해주세요.")
            return func.HttpResponse(status_code=200)

        # --- Teams: 메시지 이벤트 ---
        if msg_type == "message":
            q = (body.get("text") or "").strip()
            if not q:
                send_teams_reply(body, "질문을 입력해주세요.")
                return func.HttpResponse(status_code=200)
            send_teams_reply(body, handle_query(q))
            return func.HttpResponse(status_code=200)

        return func.HttpResponse(status_code=200)

    except Exception as e:
        logging.error("Function 처리 오류: %s", e, exc_info=True)
        return func.HttpResponse(status_code=500)
    