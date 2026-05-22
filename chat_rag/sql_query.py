import pyodbc
import logging
import os

SCHEMA = os.environ["DB_SCHEMA"]

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
        logging.info("실행 SQL: %s", sql)
        cursor.execute(sql)
        columns = [col[0] for col in cursor.description]
        rows = cursor.fetchall()
        result = [dict(zip(columns, row)) for row in rows]
        conn.close()
        return result
    except Exception as e:
        logging.error("SQL 실행 오류: %s\nSQL: %s", e, sql)
        return []


_TABLE_DESCRIPTIONS = {
    "region_summary":   "지역 정보 관리",
    "vehicle_info":     "차량 기본 정보",
    "VehicleModel":     "차량 모델 정보",
    "vehicle_status":   "차량 현재 상태 (실시간 관제용)",
    "battery_telemetry":"시간대별 배터리 센서 및 BSI 데이터",
    "bsi_feature_log":  "BSI 계산 입력 피처 로그",
    "alert_log":        "실시간 이벤트 및 알림 로그",
    "BSI_Threshold":    "BSI 상태 기준값 관리",
}


# 인스턴스 재시작 전까지 스키마를 메모리에 캐싱 (매 요청마다 DB 조회 방지)
_schema_cache: str = ""


def get_table_schema() -> str:
    global _schema_cache
    if _schema_cache:
        return _schema_cache
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("""
            SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = ?
            ORDER BY TABLE_NAME, ORDINAL_POSITION
        """, SCHEMA)
        rows = cursor.fetchall()
        conn.close()
    except Exception as e:
        logging.warning("스키마 동적 로딩 실패: %s", e)
        return ""

    tables: dict = {}
    for table_name, column_name, data_type in rows:
        tables.setdefault(table_name, []).append((column_name, data_type))

    result = []
    for table_name, columns in tables.items():
        desc = _TABLE_DESCRIPTIONS.get(table_name, "")
        header = f"[{SCHEMA}.{table_name}]" + (f" -- {desc}" if desc else "")
        result.append(header)
        for column_name, data_type in columns:
            result.append(f"- {column_name} ({data_type})")
        result.append("")

    # 첫 요청에만 DB 조회 후 _schema_cache에 저장, 이후 요청은 캐시에서 바로 반환
    _schema_cache = "\n    ".join(result)
    return _schema_cache