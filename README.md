# RAG Chatbot — 전기차 배터리 텔레메트리 질의 응답 시스템

Azure Functions 기반의 RAG(Retrieval-Augmented Generation) 챗봇입니다.  
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
| `chat_rag/__init__.py` | Azure Function 진입점. Slack / Teams 이벤트 라우팅 |
| `chat_rag/gpt_client.py` | Azure OpenAI 클라이언트. SQL 변환 및 답변 생성 |
| `chat_rag/sql_query.py` | SQL Server 연결, 스키마 조회, 쿼리 실행 |
| `chat_rag/function.json` | Azure Function HTTP 트리거 바인딩 설정 |

---

## 데이터베이스 스키마

| 테이블 | 설명 |
|--------|------|
| `region_summary` | 지역 정보 |
| `vehicle_info` | 차량 기본 정보 |
| `VehicleModel` | 차량 모델 정보 |
| `vehicle_status` | 차량 현재 상태 (실시간 관제) |
| `battery_telemetry` | 시간대별 배터리 센서 및 BSI 데이터 |
| `bsi_feature_log` | BSI 계산 입력 피처 로그 |
| `alert_log` | 실시간 이벤트 및 알림 로그 |
| `BSI_Threshold` | BSI 상태 기준값 |

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
@봇이름 서울 지역 차량 중 BSI가 가장 낮은 차량은?
@봇이름 오늘 오후에 발생한 Thermal Stress 알림 목록 보여줘
```

**Teams:**
```
i7 모델의 평균 배터리 온도는?
```

---

## 처리 흐름

1. Slack `app_mention` 또는 Teams `message` 이벤트 수신
2. Slack 요청은 HMAC-SHA256 서명 검증 및 중복 이벤트 필터링
3. Azure OpenAI가 DB 스키마를 참고해 자연어 질문을 SQL로 변환
4. Azure SQL Server에서 쿼리 실행
5. Azure OpenAI가 SQL 결과를 분석해 자연어 답변 생성
6. Slack / Teams 채널에 답변 전송
