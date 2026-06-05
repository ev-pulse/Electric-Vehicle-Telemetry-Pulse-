# Text to SQL Chatbot — 전기차 배터리 텔레메트리 질의 응답 시스템

Azure Functions 기반의 Text-to-SQL 챗봇입니다.  
자연어 질문을 SQL로 변환해 Azure SQL Database를 조회하고, Azure OpenAI GPT가 결과를 분석해 답변합니다.  
Slack 및 Microsoft Teams 채널에서 멘션으로 사용할 수 있습니다.

---

## 아키텍처

```
사용자 질문 (Slack / Teams)
        │
        ▼
  Azure Function (HTTP Trigger)
        │
        ├─ Azure OpenAI GPT  →  자연어 → SQL 변환
        │
        ├─ Azure SQL Database  →  쿼리 실행
        │
        └─ Azure OpenAI GPT  →  SQL 결과 → 자연어 답변
```

---

## 주요 파일

| 파일 | 설명 |
|------|------|
| `chatbot/__init__.py` | Azure Function 진입점. Slack / Teams 이벤트 라우팅 |
| `chatbot/gpt_client.py` | Azure OpenAI 클라이언트. SQL 변환 및 답변 생성 |
| `chatbot/sql_query.py` | SQL Server 연결, 스키마 조회, 쿼리 실행 |
| `chatbot/function.json` | Azure Function HTTP 트리거 바인딩 설정 |

---

## 데이터베이스 스키마

| 테이블 | 설명 |
|--------|------|
| `Region` | 서울 행정구역 마스터. 구/군/시도 단위 코드, 이름, 계층 구조, 지도 좌표 |
| `Vehicle` | 차량 마스터. VIN 기반 차량 ID, 모델 정보, 등록 행정구역, 차량 번호 |
| `VehicleModel` | 차량 모델 마스터. 모델명, 제조사 정보 |
| `Vehicle_Current_Status` | 차량별 최신 상태. BSI 수치, 위험 등급, 현재 위치 (차량 1대당 1행) |
| `Battery_Telemetry` | 배터리 센서 실시간 스트리밍 로그. 전압, 전류, 온도, GPS 좌표 |
| `BSI_Feature_Log` | BSI 산출용 파생 피처 로그. delta_i, delta_v, thermal_stress |
| `Alert_Log` | 실시간 이벤트 및 알림 로그. WARNING/CRITICAL 감지 내역, Slack 전송 여부 |

---

## 자치구 코드 매핑

자치구 이름으로 질문하면 행정구역 코드로 자동 변환됩니다.

| 자치구 | 코드 | 자치구 | 코드 | 자치구 | 코드 |
|--------|------|--------|------|--------|------|
| 종로구 | 010 | 동대문구 | 060 | 노원구 | 110 |
| 중구 | 020 | 중랑구 | 070 | 은평구 | 120 |
| 용산구 | 030 | 성북구 | 080 | 서대문구 | 130 |
| 성동구 | 040 | 강북구 | 090 | 마포구 | 140 |
| 광진구 | 050 | 도봉구 | 100 | 양천구 | 150 |
| 강서구 | 160 | 영등포구 | 190 | 강남구 | 230 |
| 구로구 | 170 | 동작구 | 200 | 송파구 | 240 |
| 금천구 | 180 | 관악구 | 210 | 강동구 | 250 |
|  |  | 서초구 | 220 |  |  |

광역자치단체(시/도)로 질문하면 산하 모든 구/시/군 데이터를 합산하고, "전국"으로 질문하면 17개 광역자치단체 전체를 합산합니다.

---

## 환경 변수

`local.settings.json` (로컬) 또는 Azure Function 앱 설정에 아래 값을 등록해야 합니다.

### Azure OpenAI
| 변수 | 설명 |
|------|------|
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI 엔드포인트 URL |
| `AZURE_OPENAI_KEY` | API 키 |
| `AZURE_OPENAI_API_VERSION` | API 버전 (예: `2024-02-01`) |
| `AZURE_OPENAI_DEPLOYMENT` | 배포 모델명 |

### Azure SQL Database
| 변수 | 설명 |
|------|------|
| `SQL_SERVER` | SQL Server 호스트명 |
| `SQL_DATABASE` | 데이터베이스명 |
| `SQL_USERNAME` | 사용자명 |
| `SQL_PASSWORD` | 비밀번호 |
| `DB_SCHEMA` | 스키마명 (예: `dbo`) |

### Microsoft Teams Bot
| 변수 | 설명 |
|------|------|
| `MICROSOFT_APP_ID` | Teams Bot 앱 ID |
| `MICROSOFT_APP_PASSWORD` | Teams Bot 앱 비밀번호 |
| `MICROSOFT_TENANT_ID` | Azure 테넌트 ID |

### Slack Bot
| 변수 | 설명 |
|------|------|
| `SLACK_BOT_TOKEN` | Slack Bot OAuth 토큰 |
| `SLACK_SIGNING_SECRET` | Slack 서명 검증 시크릿 |

---

## 로컬 실행

```bash
# 의존성 설치
pip install -r requirements.txt

# Azure Functions Core Tools로 실행
func start
```

---

## 사용 예시

**Slack:**
```
@봇이름 마포구 차량 중 BSI가 가장 낮은 차량은?
@봇이름 오늘 오후에 발생한 Thermal Stress 알림 목록 보여줘
@봇이름 서울 전체 Critical 상태 차량 수는?
```

**Teams:**
```
i7 모델의 평균 배터리 온도는?
강남구에서 Warning 이상 알림이 발생한 차량 목록 보여줘
```

---

## SQL 변환 규칙 정확도 체크리스트

GPT SQL 변환 결과를 검증할 때 아래 규칙별로 확인합니다.

| # | 규칙 | 테스트 질문 예시 | 확인 포인트 | 통과 기준 |
|---|------|----------------|------------|----------|
| 1 | SELECT만 허용 | "배터리 온도 데이터 삭제해줘" | 생성된 쿼리 타입 | SELECT 외 DML 미생성 |
| 2 | 스키마 prefix | "차량 목록 보여줘" | 테이블명 앞 prefix | `dbo.Vehicle` 형식 사용 |
| 3 | status 영문 값 | "위험 상태 차량은?" | WHERE status 절 | `status = 'Critical'` (한글·LIKE 금지) |
| 4 | status LIKE 금지 | "경고 상태 차량 수는?" | WHERE status 절 | `LIKE '%경고%'` 미사용 |
| 5 | 한글 N prefix | "서울 지역 차량은?" | WHERE 문자열 비교 | `N'서울'` 형식 사용 |
| 6 | 자치구 코드 변환 | "마포구 차량 현황은?" | WHERE region_code 절 | `= '140'` 형식 사용 |
| 7 | 광역 단위 집계 | "서울 전체 Critical 차량 수는?" | 집계 범위 | 서울 산하 25개 구 전체 합산 |
| 8 | 전국 집계 | "전국 배터리 이상 건수는?" | 집계 범위 | 17개 광역자치단체 전체 합산 |
| 9 | 오전/오후 시간 범위 | "오늘 오후 알림 목록 보여줘" | WHERE 시간 조건 | `12:00:00 ~ 23:59:59` |
| 10 | 단일 테이블 조회 | "차량 ID 목록 보여줘" | 불필요한 JOIN 여부 | Vehicle 한 테이블만 사용 |
| 11 | 존재하는 컬럼만 사용 | "차량 색상 알려줘" | 생성된 컬럼명 | 스키마 외 컬럼 미생성 |
| 12 | 데이터 없을 때 응답 | 조건에 해당하는 데이터가 없는 질문 | GPT 최종 답변 | "해당 조건의 데이터가 없습니다" 출력, 빈 응답 미반환 |

---

## 처리 흐름

1. Slack `app_mention` 또는 Teams `message` 이벤트 수신
2. Slack 요청은 HMAC-SHA256 서명 검증 및 중복 이벤트 필터링
3. Azure OpenAI가 DB 스키마를 참고해 자연어 질문을 SQL로 변환
4. Azure SQL Server에서 쿼리 실행
5. Azure OpenAI가 SQL 결과를 분석해 자연어 답변 생성
6. Slack / Teams 채널에 답변 전송
