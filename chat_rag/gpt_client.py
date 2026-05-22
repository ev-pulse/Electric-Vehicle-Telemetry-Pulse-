import os
from openai import AzureOpenAI
from sql_query import SCHEMA


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
    - 위 스키마에 명시된 테이블과 컬럼만 사용. 추측하거나 존재하지 않는 컬럼 사용 금지
    - SELECT 쿼리만 생성 (INSERT, UPDATE, DELETE 금지)
    - SQL 쿼리만 반환, 설명 없이
    - 모든 테이블명은 {SCHEMA}.테이블명 형식 사용
    - 테이블 JOIN은 같은 이름의 컬럼이 있을 때만 수행 (예: vehicle_id)
    - 한 테이블에 필요한 모든 컬럼이 있으면 JOIN 없이 단일 테이블에서 조회
    - 문자열 검색은 LIKE '%값%' 사용 (예: model_name LIKE '%i7%')
    - 단, vehicle_id처럼 ID 컬럼은 = 사용
    - 한글 문자열 비교 시 반드시 N prefix 사용 (예: WHERE region = N'서울', alert_type LIKE N'%Thermal Stress%')
    - 시간 조회는 timestamp 또는 alert_time 컬럼 사용
    - 오후는 12:00:00 ~ 23:59:59, 오전은 00:00:00 ~ 11:59:59
    - timestamp 컬럼은 datetime2 타입
    """

    response = client.chat.completions.create(
        model=deployment,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_question}
        ],
        max_tokens=500,
        temperature=0  # SQL 생성은 항상 동일한 결과가 나와야 하므로 0 고정
    )
    sql = response.choices[0].message.content.strip()
    # GPT가 ```sql ... ``` 형태로 감싸서 반환하는 경우 코드 블록만 추출
    if "```" in sql:
        sql = sql.split("```")[1]
        if sql.lower().startswith("sql"):
            sql = sql[3:]
    return sql.strip()


def generate_answer(user_question: str, sql_result: list[dict]) -> str:
    if not sql_result:
        return "해당 조건의 데이터가 없습니다."
    client = get_client()
    deployment = os.environ["AZURE_OPENAI_DEPLOYMENT"]

    system_prompt = """
    당신은 전기차 배터리 이상 감지 데이터 분석 전문가입니다.
    SQL 조회 결과를 바탕으로 사용자 질문에 친절하고 명확하게 답변해주세요.
    - 숫자는 구체적으로 언급
    - BSI 수치가 있으면 상태(정상/경고/위험) 기준과 함께 설명
    - delta_i, delta_v, thermal_stress 값이 있으면 이상 원인 분석에 활용
    - 데이터에 있는 값은 그대로 출력
    - SQL 결과에 없는 값은 "정보 없음"으로 표시
    - "정보 부족" 표현 사용 금지
    - 데이터가 없으면 "해당 조건의 데이터가 없습니다" 라고 답변
    """

    response = client.chat.completions.create(
        model=deployment,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": f"질문: {user_question}\n\nSQL 결과: {sql_result}"}
        ],
        max_tokens=1000,
        temperature=0.7  # 자연어 답변은 다양한 표현을 허용
    )
    return response.choices[0].message.content.strip()
