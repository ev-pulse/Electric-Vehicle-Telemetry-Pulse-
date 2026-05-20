import pyodbc
import os

# SQL Server 연결 및 쿼리 실행 관련 함수
def get_connection():
    server = os.environ["SQL_SERVER"]
    database = os.environ["SQL_DATABASE"]
    username = os.environ["SQL_USERNAME"]
    password = os.environ["SQL_PASSWORD"]

    conn_str = (
        f"DRIVER={{ODBC Driver 18 for SQL Server}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        f"UID={username};"
        f"PWD={password};"
        f"Encrypt=yes;"
        f"TrustServerCertificate=no;"
    )
    return pyodbc.connect(conn_str)


def execute_query(sql: str) -> list[dict]:
    """
    SQL 쿼리 실행 후 결과를 딕셔너리 리스트로 반환
    컬럼 추가 시 이 함수는 수정 불필요 (동적으로 처리)
    """
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(sql)
        columns = [col[0] for col in cursor.description]
        rows = cursor.fetchall()
        result = [dict(zip(columns, row)) for row in rows]
        conn.close()
        return result
    except Exception as e:
        raise Exception(f"SQL 실행 오류: {str(e)}")


def get_table_schema() -> str:
    """
    GPT에게 테이블 구조 알려주기 위한 스키마 정보
    컬럼 추가 시 여기만 수정
    """
    return """
    테이블명: dbo.ModelAlertTest

    컬럼 정보:
    - alertId (int): 고유 식별자
    - bsiValue (decimal): 이상 감지 수치값
    - triggeredFeature (varchar): 이상을 유발한 특징
    - timestamp (datetime2): 발생 시간
    - alertStatus (nvarchar): 상태값 ('정상', '이상', '위험')
    """