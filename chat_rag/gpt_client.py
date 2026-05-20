import os
from openai import AzureOpenAI


def get_client() -> AzureOpenAI:
    return AzureOpenAI(
        azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
        api_key=os.environ["AZURE_OPENAI_KEY"],
        api_version=os.environ["AZURE_OPENAI_API_VERSION"]
    )


def convert_to_sql(user_question: str, schema: str) -> str:
    client = get_client()
    deployment = os.environ["AZURE_OPENAI_DEPLOYMENT"]

    system_prompt = f"""
    당신은 SQL 전문가입니다.
    사용자의 자연어 질문을 SQL Server 쿼리로 변환해주세요.

    {schema}

    규칙:
    - SELECT 쿼리만 생성 (INSERT, UPDATE, DELETE 금지)
    - SQL 쿼리만 반환, 설명 없이
    - 오후는 12:00:00 ~ 23:59:59 기준
    - 오전은 00:00:00 ~ 11:59:59 기준
    - timestamp 컬럼은 datetime2 타입
    """

    response = client.chat.completions.create(
        model=deployment,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_question}
        ],
        max_tokens=500,
        temperature=0
    )
    sql = response.choices[0].message.content.strip()
    if "```" in sql:
        sql = sql.split("```")[1]
        if sql.lower().startswith("sql"):
            sql = sql[3:]
    return sql.strip()


def generate_answer(user_question: str, sql_result: list[dict]) -> str:
    client = get_client()
    deployment = os.environ["AZURE_OPENAI_DEPLOYMENT"]

    system_prompt = """
    당신은 차량 이상 감지 데이터 분석 전문가입니다.
    SQL 조회 결과를 바탕으로 사용자 질문에 친절하고 명확하게 답변해주세요.
    - 숫자는 구체적으로 언급
    - triggeredFeature 값이 있으면 이상 원인 설명에 활용
    - 데이터가 없으면 "해당 조건의 데이터가 없습니다" 라고 답변
    """

    response = client.chat.completions.create(
        model=deployment,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": f"질문: {user_question}\n\nSQL 결과: {sql_result}"}
        ],
        max_tokens=1000,
        temperature=0.7
    )
    return response.choices[0].message.content.strip()
