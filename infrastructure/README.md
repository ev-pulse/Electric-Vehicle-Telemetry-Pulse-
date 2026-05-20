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
