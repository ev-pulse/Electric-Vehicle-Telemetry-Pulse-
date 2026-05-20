import azure.functions as func
import json
import logging
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from sql_query import execute_query, get_table_schema
from gpt_client import convert_to_sql, generate_answer


def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("chat_rag 함수 실행")

    try:
        # 1. 사용자 질문 받기
        req_body = req.get_json()
        user_question = req_body.get("question")

        if not user_question:
            return func.HttpResponse(
                json.dumps({"error": "질문을 입력해주세요."}, ensure_ascii=False),
                status_code=400,
                mimetype="application/json"
            )

        logging.info(f"질문: {user_question}")

        # 2. 테이블 스키마 가져오기
        schema = get_table_schema()

        # 3. 자연어 → SQL 변환
        sql_query = convert_to_sql(user_question, schema)
        logging.info(f"생성된 SQL: {sql_query}")

        # 4. SQL 실행
        sql_result = execute_query(sql_query)
        logging.info(f"SQL 결과: {sql_result}")

        # 5. 결과 → 자연어 답변 생성
        answer = generate_answer(user_question, sql_result)
        logging.info(f"답변: {answer}")

        return func.HttpResponse(
            json.dumps({
                "question": user_question,
                "sql": sql_query,
                "answer": answer
            }, ensure_ascii=False),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logging.error(f"오류 발생: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": str(e)}, ensure_ascii=False),
            status_code=500,
            mimetype="application/json"
        )