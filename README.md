# ⚡ EV-Pulse — Electric Vehicle Telemetry Pulse

전기차 배터리 텔레메트리를 실시간으로 수집·분석해 **이상 전조를 조기에 탐지**하고,
자체 지표 **BSI(Battery Stress Index)** 로 차량 상태를 정량화하는 Azure 기반 모니터링 시스템.

> 배터리는 갑자기 죽지 않는다. 열폭주·셀 열화에는 수십 분~수 시간의 전조 신호가 있고,
> 그 구간을 잡아 "수리 가능 여부"가 아니라 "언제 멈추느냐"를 관리하는 것이 EV-Pulse의 목표이다.

---

## 프로젝트 목표

1. 배터리 열화 메커니즘을 반영한 EV 상태 실시간 모니터링 시스템 구축
2. 자체 기준(BSI)을 정의하고, 그 기준으로 항목별 이상 여부를 판단
3. 장기적으로 차량 생애주기 데이터를 축적해 추후 차세대 배터리 개선에 활용

### 왜 필요한가 (요약)

전기차 보급이 빠르게 늘면서 배터리 안전성·유지보수 비용·중고 잔존가치·OTA 오류·규제 대응 문제가 동시에 커지고 있다. 사후(정비·리콜) 대응은 비용·시간 부담이 크므로, 차량 데이터를 실시간 분석해 사전 예방형 품질 관리로 전환할 필요가 있다. 배터리는 EV 원가의 30~40%를 차지하는 고가 부품이고, EU는 2027년부터 디지털 배터리 여권을 요구하는 등 이력 관리가 규제 대응의 핵심이 되고 있다.

---

## 핵심 개념: BSI (Battery Stress Index)

배터리 상태에 영향을 주는 주요 stress feature들의 이상도(A·)를 가중 합산해 산출하는 종합 이상 지표.
가중치는 NASA Battery Dataset 분석을 근거로 설정한다.

```
BSI =
  0.4830 × |Z_Delta_I|
+ 0.2218 × |Z_Delta_V|
+ 0.1027 × |Z_Thermal_Stress|
+ 0.0992 × |Z_Battery_Current|
+ 0.0933 × |Z_Battery_Voltage|

Z_Thermal_Stress =
  0.8 × Z_Joule_Heating_Stress
+ 0.2 × Z_Thermal_Temperature_70min
```

| 피처 | 의미 | 가중치 |
|------|------|--------|
| AΔI | 전류 변화량 이상도 | 0.3140 |
| AΔP | 전력 변화량 이상도 | 0.2933 |
| AΔV | 전압 변화량 이상도 | 0.1442 |
| AJHS | Joule Heating 기반 thermal stress 이상도 | 0.0668 |
| AI | 배터리 전류 이상도 | 0.0645 |
| AV | 배터리 전압 이상도 | 0.0607 |
| AP | 배터리 전력 이상도 | 0.0565 |

> BSI 값은 Azure ML(LightGBM)이 산출한다. 들어온 텔레메트리를 모델에 추론시키고 그 출력값을 해당 차량의 BSI로 기록하며, 이를 기준으로 정상/위험을 판별한다. 시뮬레이터·Stream Analytics는 BSI를 계산하지 않는다.

설명 가능성을 위해 단순 점수만 보여주지 않고 "셀 전압 편차 증가", "급속충전 후 냉각 지연" 같은 이상 원인(피처)을 함께 제시하는 것을 지향한다.

---

## 아키텍처

[아키텍처](docs/architecture.png)
[시연 영상 보기](docs/evpulse_시연영상.mp4)
[발표 자료 보기](docs/EV-Pulse.pptx.pdf)

**모델 레이어**

- NASA Battery Dataset → BSI 가중치·임계값 근거
- BMW i3 Dataset → 실차 기반 μ/σ 파라미터
- 프로덕션 모델 `ev-lgbm-inference-artifact:8` / 엔드포인트 `ev-anomaly-endpoint-6403dedf` / 배포 `purple2` / `Standard_DS2_v2`

---

## 저장소 구조

```
.
├── README.md
├── asaproj.json               # Stream Analytics 프로젝트 정의
├── .gitignore
│
├── chatbot/                   # Text-to-SQL 챗봇 (Azure Function)
│   ├── __init__.py            #   Slack / Teams 이벤트 라우팅
│   ├── gpt_client.py          #   자연어 → SQL 변환 및 답변 생성
│   ├── sql_query.py           #   SQL Server 연결 및 쿼리 실행
│   ├── function.json
│   └── README.md
│
├── Python_Simulator/          # 차량 텔레메트리 재생 시뮬레이터
│   ├── simulator.py           #   VIN 매핑·합성차량 증강·파생변수 계산·IoT 전송
│   ├── config.py              #   IoT Hub·임계값·증강 파라미터
│   ├── requirements.txt
│   └── README.md
│
├── infrastructure/            # Infrastructure as Code (Bicep)
│   ├── main.bicep             #   핵심 5개 리소스 직접 설계
│   ├── template.bicep         #   Portal Export 기반 전체 스냅샷
│   ├── main.json              #   main.bicep 컴파일(ARM)
│   ├── ml-deployment-purple2.yml
│   ├── parameters.json        #   파라미터 템플릿(YOUR_* 플레이스홀더)
│   └── README.md
│
└── .github/workflows/
    └── infra-deploy.yml       # CI/CD (Bicep Lint → What-If → Deploy)
```

---

## 핵심 구성 요소

### 1. Python Simulator

전처리된 BMW CSV(약 200,000행·실차 70대)를 실시간 차량 데이터처럼 IoT Hub로 재생한다.

- 차량 100대: 실차 70대 + 가우시안 증강 15대(VIN-071~085) + 열화 시뮬레이션 15대(VIN-086~100)
- 파생변수만 계산: `ΔI = I(t)−I(t−1)`, `ΔV = V(t)−V(t−1)`, `JHS = I² × T`
- Z-score·BSI·상태 판별은 계산하지 않음 → Azure ML 담당
- 이상 센서값 1% 확률 주입(파이프라인 테스트), 서울 25개 구 위경도 매핑

```bash
cd Python_Simulator
pip install -r requirements.txt
python3 simulator.py --dry-run      # 콘솔 출력만
python3 simulator.py                # IoT Hub 전송 (.env 필요)
```

### 2. Infrastructure (Bicep)

전체 Azure 환경을 코드로 재현. 두 Bicep을 의도적으로 분리:

| 파일 | 용도 |
|------|------|
| `main.bicep` | 핵심 5개(IoT Hub·SQL·Stream Analytics·Storage·Logic Apps) 직접 설계 |
| `template.bicep` | Portal Export 전체 스냅샷 — ML Workspace·OpenAI·Key Vault·Function App·Bot 포함, 민감값 제거 |

리전 고정: 실시간 파이프라인 전체를 `koreacentral`로 고정(레이턴시·오배포 방지). Azure OpenAI만 gpt-4o-mini 가용성 때문에 `eastus`.

### 3. 알림 (Logic Apps)

SQL `[dbo].[ModelAlertTest]` 테이블을 3분 간격 폴링하다 이상/위험 감지 시 Slack으로 전송(Teams 커넥션도 정의됨). KST(UTC+9) 변환, BSI 수치·이상 피처·감지 시각 포함.

### 4. Text-to-SQL 챗봇

Function App(Python) + Azure OpenAI `gpt-4o-mini`(`evpulse-gpt`) 기반 Text-to-SQL. 자연어 질의를 SQL로 변환해 `evpulse` DB를 조회한다. 자세한 내용은 [chatbot/README.md](chatbot/README.md) 참고.

### 5. CI/CD

`infrastructure/**` 변경 시 트리거. PR → `validate`(Bicep Lint + what-if), main push → `deploy`. 인증은 Service Principal(`AZURE_CREDENTIALS`), 민감값은 GitHub Secrets 런타임 주입.

---

## 배포 / 실행

```bash
az group create --name evpulse-rg --location koreacentral

# 핵심 파이프라인
az deployment group create \
  --resource-group evpulse-rg \
  --template-file infrastructure/main.bicep \
  --parameters @infrastructure/parameters.json

# ML 배포 재현
az ml online-deployment create \
  --file infrastructure/ml-deployment-purple2.yml \
  --workspace-name ev-modeling-ML \
  --resource-group evpulse-rg --all-traffic
```

비밀값·연결 문자열·자격증명은 코드에 포함하지 않으며(`@secure()` + GitHub Secrets), `.env`·`*.local.json`·`*.csv`·키/인증서는 `.gitignore` 처리한다.

---

## 비즈니스 가치 (이해관계자별)

| 이해관계자 | Pain Point | EV-Pulse 가치 |
|-----------|-----------|--------------|
| 완성차 제조사(OEM) | 리콜 비용·품질 이슈, 실운행 데이터 부족 | Fleet 단위 열화 패턴 분석, 배치·연식·지역별 이상 탐지, OTA/BMS 개선 |
| 배터리 제조사 | 셀 품질 편차·배치 추적 어려움 | 셀 단위 열화·전압 불균형 분석으로 차세대 셀 설계 지원 |
| Fleet 운영사(렌터카·물류·택시) | 운행 중단 손실, 교체 비용 | 예방 정비, 위험 차량 우선 관리, 배차 전 제외로 운행 완료율 보장 |
| 보험사 | EV 화재·사고 보험 비용 증가 | 위험 패턴 기반 사고 예측, 탑재 차량 보험료 할인(B2B) |
| 중고차 시장/수출 | 배터리 상태 신뢰 부족 | 텔레메트리 이력 기반 배터리 건강도 인증 |
| 개인 소유자 | 갑작스러운 이상·교체 비용 | 이상 전조 알림, 수명 관리, 유지비 절감 |
| 공공/ESG | EV 안전, 폐배터리 증가 | 사고율 감소, 수명 연장으로 자원 효율·지속가능성 |

