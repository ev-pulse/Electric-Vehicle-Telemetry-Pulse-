# EV-Pulse Infrastructure as Code (Bicep)

Azure Portal "템플릿 내보내기"로 추출한 인프라를 보안 처리하고 주석을 추가한 Bicep 파일입니다.  
이 파일 하나로 EV-Pulse 전체 Azure 환경을 재현할 수 있습니다.

## 리전 고정 전략

| 리소스 | 리전 | 이유 |
|--------|------|------|
| Azure OpenAI (`evpulse-azoai`) | `eastus` | Korea Central은 gpt-4o-mini 미지원 |
| IoT Hub, Stream Analytics, SQL, Logic Apps | `koreacentral` | 데이터 레이턴시 최소화 |

> 리전은 파라미터로 열지 않고 **의도적으로 코드에 고정**합니다.  
> 오배포로 인해 아키텍처가 깨지는 휴먼 에러를 원천 차단하기 위한 설계 결정입니다.

## 배포 방법

### 1. 파라미터 파일 준비
```bash
cp parameters.json parameters.local.json
# parameters.local.json 열어서 YOUR_* 값을 실제 값으로 교체
# 이 파일은 .gitignore에 의해 Git 추적에서 제외됨
```

### 2. 배포 전 변경사항 확인 (Dry-run)
```bash
az deployment group what-if \
  --resource-group evpulse-rg \
  --template-file template.bicep \
  --parameters @parameters.local.json
```

### 3. 실제 배포
```bash
az deployment group create \
  --resource-group evpulse-rg \
  --template-file template.bicep \
  --parameters @parameters.local.json
```

## 파일 구조

```
infrastructure/
├── template.bicep        # 전체 인프라 정의 (민감값 제거, 주석 추가)
├── parameters.json       # 파라미터 템플릿 (YOUR_* 플레이스홀더)
├── .gitignore            # parameters.local.json 등 시크릿 제외
└── README.md             # 이 파일
```

## 보안 처리 내역

원본 Export Template 대비 변경된 보안 처리:

| 항목 | 변경 전 | 변경 후 |
|------|---------|---------|
| `tenantId` | 하드코딩 | `param tenantId` 참조 |
| `objectId` | 하드코딩 | `param keyVaultObjectId` 참조 |
| `subscriptionId` | 하드코딩 (6곳) | `param subscriptionId` 참조 |

**main.bicep 추가

본 프로젝트의 main.bicep은 단순한 리소스 나열이 아닌, 모듈화(Modularity)와 재사용성(Reusability)을 고려하여 설계되었습니다.

1. 모듈 아키텍처
main.bicep은 루트 진입점으로서 각 서비스 단위를 모듈로 호출합니다.

iot.bicep: IoT Hub 및 장치 연결 설정

analytics.bicep: Stream Analytics 및 저장소 연동

storage.bicep: 결과 데이터 저장을 위한 SQL 및 Data Lake

ai.bicep: OpenAI 서비스 및 보안 키 설정

Why? 리소스 간 의존성을 모듈별로 명확히 분리하여, 특정 리소스 수정 시 전체 환경에 미치는 영향을 최소화했습니다.

2. 관리 철학: "Infrastructure as Code, Not just as Script"
우리는 다음과 같은 원칙으로 인프라 코드를 관리합니다:

Idempotency (멱등성): 동일한 코드를 여러 번 배포해도 결과는 항상 동일하게 유지됩니다.

Declarative (선언적 정의): "어떻게(How)"가 아닌 "무엇을(What)" 상태로 만들지 정의하여, 실제 환경과 코드 간의 간극을 없앴습니다.

Security by Design:

리소스 생성 시 Key Vault를 통해 민감한 정보를 관리합니다.

하드코딩된 ID(Tenant, Subscription)를 일체 제거하고 param으로 추상화했습니다.

3. 유지보수 가이드 (How to extend)
새로운 리소스를 추가할 때 다음 절차를 따르세요:

신규 모듈 생성: infrastructure/modules/ 하위에 새로운 .bicep 파일 생성.

main.bicep 호출: 루트 main.bicep 파일 내에서 모듈을 호출(Module call)하여 연결.

파라미터 업데이트: parameters.json에 신규 리소스에 필요한 설정값 추가.

Dry-run 검증: az deployment group what-if 명령어로 변경 영향도 반드시 확인.
