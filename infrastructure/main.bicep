// ============================================================
// EV-Pulse — Azure Infrastructure as Code
// Author  : Dana Kim  |  Team : 4DT Team 1
// Purpose : Reproducible deployment of EV-Pulse core monitoring pipeline
//
// [이 파일의 역할]
//   핵심 5개 파이프라인 리소스를 처음부터 직접 설계한 Bicep 파일.
//   → template.bicep (Export 기반 전체 스냅샷)과 별도로 관리.
//   → 리소스 간 의존성, 파라미터 설계, 태그 전략을 직접 결정.
//
// [리전 고정 전략 — Explicit Location Locking]
//   실시간 파이프라인 전체(IoT Hub · SA · SQL · Logic Apps)를
//   koreacentral로 고정. 파라미터로 열어두지 않는 이유:
//   → 리전이 달라지면 리소스 간 레이턴시가 생기고 아키텍처가 깨짐.
//   → 오배포로 인한 휴먼 에러를 원천 차단하기 위한 의도적 설계 결정.
//   (Azure OpenAI는 gpt-4o-mini 가용성으로 eastus 고정 — template.bicep 참고)
//
// [배포]
//   az deployment group create \
//     --resource-group evpulse-rg \
//     --template-file main.bicep \
//     --parameters @parameters.json
// ============================================================

// ── Parameters ──────────────────────────────────────────────

@description('Deployment environment — dev/staging/prod')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

// [리전 고정] koreacentral — 데이터 레이턴시 최소화 + 오배포 방지
// 파라미터로 선언하되 기본값 고정.
// 변경 시 파이프라인 전체에 영향을 주므로 반드시 팀 합의 후 수정할 것.
@description('Azure region — 파이프라인 레이턴시 최소화를 위해 koreacentral 고정')
param location string = 'koreacentral'

@description('Project prefix — 모든 리소스명 앞에 붙는 식별자')
param projectPrefix string = 'evpulse'

@description('IoT Hub SKU — S1: 팀 프로젝트 / F1: 개인 테스트용 무료')
@allowed(['F1', 'S1'])
param iotHubSku string = 'S1'

@description('Azure SQL administrator login name')
param sqlAdminLogin string = 'sqluser'

@description('Azure SQL administrator password')
@secure()
param sqlAdminPassword string

@description('Stream Analytics Streaming Units — 1이 최소, 비용 최소')
param saStreamingUnits int = 1

// ── Variables ───────────────────────────────────────────────
// 모든 리소스명을 prefix + environment 조합으로 통일
// → 동일 subscription에서 dev/prod 환경을 충돌 없이 공존 가능

var iotHubName         = '${projectPrefix}-iothub-${environment}'
var sqlServerName      = '${projectPrefix}-sqlserver-${environment}'
var sqlDbName          = '${projectPrefix}-db-${environment}'
var saJobName          = '${projectPrefix}-sa-job-${environment}'
var logicAppName       = '${projectPrefix}-logic-app-${environment}'
var storageAccountName = '${projectPrefix}storage${environment}'  // 소문자+숫자만 허용

// ── Resource 1: IoT Hub ─────────────────────────────────────
// 역할: 차량 시뮬레이터(VIN-001~003)로부터 배터리 텔레메트리 수신
// 의존성: 없음 — 파이프라인 최상위 진입점
// 설계 결정: partitionCount=2 → Stream Analytics consumer group 전용

resource iotHub 'Microsoft.Devices/IotHubs@2021-07-02' = {
  name: iotHubName
  location: location
  sku: {
    name: iotHubSku
    capacity: 1
  }
  properties: {
    eventHubEndpoints: {
      events: {
        retentionTimeInDays: 1
        partitionCount: 2          // Stream Analytics consumer group용
      }
    }
    routing: {
      fallbackRoute: {
        name: '$fallback'
        source: 'DeviceMessages'
        condition: 'true'
        endpointNames: ['events']
        isEnabled: true
      }
    }
    cloudToDevice: {
      maxDeliveryCount: 10
      defaultTtlAsIso8601: 'PT1H'
    }
    minTlsVersion: '1.2'          // 보안: TLS 1.2 이상만 허용
    disableLocalAuth: false
  }
  tags: {
    project: 'ev-pulse'
    environment: environment
    role: 'ingestion'             // 태그 전략: role로 리소스 역할 명시
  }
}

// ── Resource 2: Azure SQL Server ────────────────────────────
// 역할: 텔레메트리 · 베이스라인(μ/σ) · 상태 로그(state_log) 저장
// 의존성: 없음 — SQL DB / 방화벽이 이 서버에 의존
// 설계 결정: S0 (10 DTU) — MVP 10일 기준 충분, 월 ~$5 비용 최소화

resource sqlServer 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword  // @secure() param — 코드에 값 없음
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
  tags: {
    project: 'ev-pulse'
    environment: environment
    role: 'storage'
  }
}

// SQL Database — 서버에 종속 (parent로 명시적 의존성)
resource sqlDb 'Microsoft.Sql/servers/databases@2022-05-01-preview' = {
  parent: sqlServer              // parent 선언 → sqlServer 생성 완료 후 자동 생성
  name: sqlDbName
  location: location
  sku: {
    name: 'S0'
    tier: 'Standard'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 268435456000   // 250 GB
  }
  tags: {
    project: 'ev-pulse'
    environment: environment
    role: 'storage'
  }
}

// SQL 방화벽 — Azure 내부 서비스(Stream Analytics, Logic Apps) 접근 허용
// 0.0.0.0 → 0.0.0.0 : Azure 서비스만 허용하는 Azure 표준 패턴
resource sqlFirewallAzureServices 'Microsoft.Sql/servers/firewallRules@2022-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// ── Resource 3: Stream Analytics Job ────────────────────────
// 역할: IoT Hub 수신 → Moving Average → AnomalyScore 계산 → SQL 저장
// 의존성: Job 리소스 자체는 독립 생성 가능
//         입출력(IoT Hub 연결, SQL 출력)은 연결 문자열 포함으로 포털/CLI 별도 설정
//         → 보안상 Bicep에 연결 문자열 포함하지 않음 (의도적 설계)
// 참고: 쿼리는 /sql/sa_query.sql 에서 관리

resource streamAnalyticsJob 'Microsoft.StreamAnalytics/streamingjobs@2021-10-01-preview' = {
  name: saJobName
  location: location
  properties: {
    sku: {
      name: 'Standard'
    }
    eventsOutOfOrderPolicy: 'Adjust'   // 순서 어긋난 이벤트: 조정 후 처리 (드롭 아님)
    outputErrorPolicy: 'Stop'          // 출력 오류 시 Job 중단 → 데이터 유실 방지
    eventsOutOfOrderMaxDelayInSeconds: 5
    eventsLateArrivalMaxDelayInSeconds: 5
    dataLocale: 'en-US'
    compatibilityLevel: '1.2'
    jobType: 'Cloud'
  }
  tags: {
    project: 'ev-pulse'
    environment: environment
    role: 'processing'
    note: 'I/O configured separately — see /sql/sa_query.sql'
  }
}

// ── Resource 4: Storage Account ─────────────────────────────
// 역할: Logic Apps 런타임 스토리지 (워크플로우 상태, 실행 이력 저장)
// 의존성: Logic Apps가 이 스토리지에 의존
// 설계 결정: Standard_LRS — 단일 리전 복제, 비용 최소

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false   // 보안: Blob 공개 접근 차단
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
  }
  tags: {
    project: 'ev-pulse'
    environment: environment
    role: 'runtime-storage'
  }
}

// ── Resource 5: Logic Apps ───────────────────────────────────
// 역할: SQL CRITICAL 상태 30초 간격 감지 → Teams ev-pulse-alerts 채널 알림
// 의존성: storageAccount (런타임), sqlDb (트리거 폴링 대상)
// 설계 결정: Function App 대신 Logic Apps 채택
//   → 코드 없이 Teams Webhook 연동 가능
//   → 10일 MVP 내 개발·배포 오버헤드 최소화 (ADR Q1)
// 주의: 워크플로우 정의(트리거·액션)는 포털 구성 후 이 파일에 반영 예정

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {}
      actions: {}
    }
    parameters: {}
  }
  tags: {
    project: 'ev-pulse'
    environment: environment
    role: 'alerting'
    trigger: 'SQL CRITICAL state (30s interval)'
    action: 'Teams webhook → ev-pulse-alerts'
  }
  dependsOn: [
    storageAccount   // 런타임 스토리지 먼저 생성
    sqlDb            // 트리거 대상 DB 먼저 생성
  ]
}

// ── Outputs ─────────────────────────────────────────────────
// 배포 완료 후 시뮬레이터 연결 · SA 입출력 설정에 필요한 값 출력

output iotHubName string = iotHub.name
output iotHubResourceId string = iotHub.id

output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlDbName string = sqlDb.name

output saJobName string = streamAnalyticsJob.name
output logicAppName string = logicApp.name

output deploymentSummary object = {
  author: 'Dana Kim'
  environment: environment
  location: location
  resources: [
    'IoT Hub (${iotHubSku})'
    'SQL Server + Database (S0 / 10DTU)'
    'Stream Analytics Job (SU: ${saStreamingUnits})'
    'Storage Account (Standard_LRS)'
    'Logic Apps (CRITICAL → Teams)'
  ]
}
