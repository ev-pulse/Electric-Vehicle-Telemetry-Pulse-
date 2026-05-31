# ⚡ EV-Pulse — Infrastructure as Code (Bicep)

> Azure 기반 EV 배터리 이상 탐지 시스템의 전체 인프라를 코드로 관리합니다.  
> **이 레포 하나로 EV-Pulse 전체 Azure 환경을 재현할 수 있습니다.**

---

## 📐 시스템 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                        EV-Pulse Pipeline                        │
│                                                                 │
│  🚗 Vehicle Simulator          ☁️  Azure Cloud                  │
│  ┌──────────────┐              ┌──────────────────────────────┐ │
│  │ VIN-001      │──MQTT/HTTPS─▶│  IoT Hub (koreacentral)      │ │
│  │ VIN-002      │              │  evpulse-iothub              │ │
│  │ VIN-003      │              └──────────┬───────────────────┘ │
│  └──────────────┘                         │ Event Stream        │
│                                           ▼                     │
│                              ┌──────────────────────────────┐   │
│                              │  Stream Analytics Job        │   │
│                              │  evpulse-sa-job              │   │
│                              │                              │   │
│                              │  · Moving Average (μ/σ)      │   │
│                              │  · Z-Score AnomalyScore 계산 │   │
│                              │  · NORMAL / WARNING /        │   │
│                              │    CRITICAL 상태 판정        │   │
│                              └──────────┬───────────────────┘   │
│                                         │ SQL Output            │
│                                         ▼                       │
│                              ┌──────────────────────────────┐   │
│                              │  Azure SQL Database          │   │
│                              │  evpulse-db                  │   │
│                              │                              │   │
│                              │  · telemetry (원시 데이터)   │   │
│                              │  · baseline (VIN별 μ/σ)      │   │
│                              │  · state_log (상태 이력)     │   │
│                              └──────┬───────────┬───────────┘   │
│                                     │           │               │
│                          CRITICAL   │           │ Query         │
│                          감지(30s)  │           │               │
│                                     ▼           ▼               │
│                    ┌──────────────────┐  ┌──────────────────┐   │
│                    │  Logic Apps      │  │  Power BI        │   │
│                    │  evpulse-logic   │  │  Dashboard       │   │
│                    │  -app            │  │  (실시간 모니터) │   │
│                    └────────┬─────────┘  └──────────────────┘   │
│                             │ Webhook                           │
│                             ▼                                   │
│                    ┌──────────────────┐  ┌──────────────────┐   │
│                    │  Microsoft Teams │  │  Azure OpenAI    │   │
│                    │  #ev-pulse-alerts│  │  Text-to-SQL Bot │   │
│                    └──────────────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────────────────────┘

[ML 레이어]
  Azure ML Workspace → LGBM 이상 탐지 모델 학습 · 배포
  NASA Battery Dataset → BSI 가중치 도출
  BMW i3 Dataset      → 실차 기반 μ/σ 파라미터 추출

[프로덕션 모델]
  엔드포인트 : ev-anomaly-endpoint-6403dedf
  배포명     : purple2
  모델       : ev-lgbm-inference-artifact  v8
  재배포     : infrastructure/ml-deployment-purple2.yml 참고
```

---

## 🔄 CI/CD 파이프라인

```
┌──────────────────────────────────────────────────────────────┐
│                  GitHub Actions Workflow                      │
│                                                              │
│  개발자 로컬                  GitHub                 Azure   │
│  ┌─────────┐   git push    ┌─────────┐            ┌───────┐  │
│  │ Bicep   │──────────────▶│ feature │            │       │  │
│  │ 수정    │   (PR 생성)   │ branch  │            │  RG   │  │
│  └─────────┘               └────┬────┘            │       │  │
│                                 │ PR trigger       │       │  │
│                                 ▼                  │       │  │
│                          ┌─────────────┐           │       │  │
│                          │  validate   │           │       │  │
│                          │  ─────────  │           │       │  │
│                          │ 1.az bicep  │           │       │  │
│                          │   build     │           │       │  │
│                          │   (Lint)    │           │       │  │
│                          │ 2.what-if   │──────────▶│ 변경  │  │
│                          │  (미리보기) │  read-only│ 사항  │  │
│                          └──────┬──────┘  쿼리    │ 확인  │  │
│                                 │                  │       │  │
│                   main 머지     │                  │       │  │
│                          ┌──────▼──────┐           │       │  │
│                          │   deploy    │           │       │  │
│                          │  ─────────  │           │       │  │
│                          │ needs:      │           │       │  │
│                          │  validate   │           │       │  │
│                          │             │──────────▶│ 실제  │  │
│                          │ az deploy   │  배포     │ 배포  │  │
│                          │ group create│           │ 완료  │  │
│                          └─────────────┘           └───────┘  │
│                                                              │
│  트리거 조건                                                 │
│  · push to main        → validate + deploy (순서 보장)      │
│  · pull_request        → validate only (what-if 확인)       │
│  · workflow_dispatch   → 수동 실행 버튼                      │
│  · paths: infrastructure/** → 인프라 변경 시에만 실행       │
└──────────────────────────────────────────────────────────────┘
```

### 파이프라인 보안 설계

| 항목 | 방식 |
|------|------|
| Azure 인증 | Service Principal (`AZURE_CREDENTIALS`) — GitHub Secrets 보관 |
| 민감값 전달 | GitHub Secrets → `--parameters` 런타임 주입 |
| 코드 노출 | 연결 문자열, 비밀번호 일체 코드 미포함 |
| 배포 추적 | `--name deploy-${{ github.sha }}` — 커밋 해시로 배포 이력 관리 |

---

## 📁 파일 구조

```
infrastructure/
├── main.bicep              # 핵심 파이프라인 5개 리소스 (직접 설계)
│                           #   IoT Hub / SQL Server+DB / Stream Analytics
│                           #   Storage Account / Logic Apps
├── template.bicep          # Azure Portal Export 기반 전체 스냅샷
│                           #   ML Workspace, OpenAI, Key Vault 등 포함
│                           #   민감값 제거 + 주석 추가 처리
├── parameters.json         # 파라미터 템플릿 (YOUR_* 플레이스홀더)
├── parameters_local.json   # 실제 값 (gitignore — 절대 커밋 금지)
├── .gitignore
└── README.md
.github/
└── workflows/
    └── infra-deploy.yml    # CI/CD 파이프라인 정의
```

---

## 🌏 리전 고정 전략

| 리소스 | 리전 | 이유 |
|--------|------|------|
| IoT Hub, Stream Analytics, SQL, Logic Apps | `koreacentral` | 데이터 레이턴시 최소화 |
| Azure OpenAI (`evpulse-azoai`) | `eastus` | Korea Central gpt-4o-mini 미지원 |

> 리전은 파라미터로 열지 않고 **의도적으로 코드에 고정**합니다.  
> 오배포로 인해 아키텍처가 깨지는 휴먼 에러를 원천 차단하기 위한 설계 결정입니다.

---

## 🚀 배포 방법

### 사전 준비

```bash
# Azure CLI 로그인
az login

# 리소스 그룹 생성 (최초 1회)
az group create --name evpulse-rg --location koreacentral
```

### 1. 파라미터 파일 준비

```bash
cp parameters.json parameters_local.json
# parameters_local.json 열어서 YOUR_* 값을 실제 값으로 교체
# 이 파일은 .gitignore에 의해 Git 추적에서 제외됨 — 절대 커밋하지 말 것
```

### 2. 배포 전 변경사항 확인 (Dry-run)

```bash
az deployment group what-if \
  --resource-group evpulse-rg \
  --template-file template.bicep \
  --parameters @parameters_local.json
```

### 3. 실제 배포

```bash
# main.bicep — 핵심 파이프라인 5개 리소스
az deployment group create \
  --resource-group evpulse-rg \
  --template-file main.bicep \
  --parameters @parameters_local.json

# template.bicep — 전체 스냅샷 (ML Workspace, OpenAI 포함)
az deployment group create \
  --resource-group evpulse-rg \
  --template-file template.bicep \
  --parameters @parameters_local.json
```

### 4. 배포 결과 확인

```bash
# 배포 이력 조회
az deployment group list \
  --resource-group evpulse-rg \
  --output table

# 배포 출력값 확인 (IoT Hub 이름, SQL FQDN 등)
az deployment group show \
  --resource-group evpulse-rg \
  --name <deployment-name> \
  --query properties.outputs
```

---

## 🔐 GitHub Actions 설정

### 필수 GitHub Secrets

레포 → Settings → Secrets and variables → Actions 에서 등록:

| Secret 이름 | 설명 |
|-------------|------|
| `AZURE_CREDENTIALS` | Service Principal JSON 전체 |
| `AZURE_RG` | `evpulse-rg` |
| `TENANT_ID` | Azure Tenant ID |
| `SUBSCRIPTION_ID` | Azure Subscription ID |
| `KV_OBJECT_ID` | Key Vault Object ID |
| `IOTHUB_CONNECTION_STRING` | IoT Hub 연결 문자열 |
| `STORAGE_CONTAINER_PATH` | Storage Container Path |
| `SQL_ADMIN_PASSWORD` | SQL Server 관리자 비밀번호 |

### Service Principal 생성

```bash
az ad sp create-for-rbac \
  --name "evpulse-github-actions" \
  --role contributor \
  --scopes /subscriptions/{SUBSCRIPTION_ID}/resourceGroups/evpulse-rg \
  --json-auth
```

출력된 JSON 전체를 `AZURE_CREDENTIALS` Secret에 등록합니다.

---

## 🔒 보안 처리 내역

Azure Portal Export 원본 대비 변경된 보안 처리:

| 항목 | 변경 전 | 변경 후 |
|------|---------|---------|
| `tenantId` | 하드코딩 | `@secure() param tenantId` |
| `objectId` | 하드코딩 | `@secure() param keyVaultObjectId` |
| `subscriptionId` | 하드코딩 (6곳) | `param subscriptionId` 참조 |
| `sqlAdminPassword` | 미선언 | `@secure() @minLength(8) param sqlAdminPassword` |
| 연결 문자열 | 하드코딩 | GitHub Secrets → 런타임 주입 |
| Log Analytics 기본 리소스 | 808개 (Azure 한도 초과) | 103개 (자동 생성 항목 제거) |

---

## 🗂️ 재현 파일 구조

리소스 그룹이 삭제되더라도 이 레포 하나로 전체 환경을 복구할 수 있습니다.

```
infrastructure/
├── template.bicep              ← 전체 Azure 인프라 재현 (ML Workspace, IoT Hub 등)
├── ml-deployment-purple2.yml   ← purple2 ML 배포 재현 (모델 버전·compute 설정 포함)
├── parameters.json             ← 파라미터 템플릿 (YOUR_* 값을 실제 값으로 교체)
└── README.md                   ← 재배포 명령어 및 전체 아키텍처 문서
```

---

## 🔁 전체 환경 재구축 순서 (리소스 그룹 삭제 후)

### Step 1 — 리소스 그룹 생성

```bash
az group create \
  --name 4dt_team_1 \
  --location koreacentral
```

### Step 2 — 전체 Azure 인프라 배포 (template.bicep)

```bash
az deployment group create \
  --resource-group 4dt_team_1 \
  --template-file infrastructure/template.bicep \
  --parameters @infrastructure/parameters.json \
    tenantId="YOUR_TENANT_ID" \
    keyVaultObjectId="YOUR_OBJECT_ID" \
    subscriptionId="YOUR_SUBSCRIPTION_ID" \
    sqlAdminPassword="YOUR_SQL_PASSWORD"
```

> IoT Hub, SQL, Stream Analytics, ML Workspace, Function App, Azure Bot 등 전체 리소스가 이 한 번의 명령으로 생성됩니다.

### Step 3 — ML 프로덕션 모델 배포 (purple2)

```bash
# ML extension 설치 (최초 1회)
az extension add --name ml

# purple2 배포 재현
az ml online-deployment create \
  --file infrastructure/ml-deployment-purple2.yml \
  --workspace-name ev-modeling-ML \
  --resource-group 4dt_team_1 \
  --all-traffic
```

| 항목 | 값 |
|------|----|
| 엔드포인트 | `ev-anomaly-endpoint-6403dedf` |
| 배포명 | `purple2` |
| 모델 | `ev-lgbm-inference-artifact:8` |
| 알고리즘 | LightGBM (BSI 기반 이상 탐지) |
| 인스턴스 | `Standard_DS2_v2` × 1 |

> ML Online Deployment는 ARM/Bicep API 제약으로 YAML로 별도 관리합니다.  
> `ml-deployment-purple2.yml`에 모든 설정이 보존되어 있습니다.

---

## 📋 배포 리소스 목록 (main.bicep)

| 리소스 | 이름 패턴 | 역할 |
|--------|-----------|------|
| IoT Hub | `evpulse-iothub-{env}` | 차량 텔레메트리 수신 |
| SQL Server | `evpulse-sqlserver-{env}` | 텔레메트리 · 상태 저장 |
| SQL Database | `evpulse-db-{env}` | S0 / 10DTU |
| Stream Analytics | `evpulse-sa-job-{env}` | 실시간 이상 탐지 처리 |
| Storage Account | `evpulsestorage{env}` | Logic Apps 런타임 |
| Logic Apps | `evpulse-logic-app-{env}` | CRITICAL → Teams 알림 |
