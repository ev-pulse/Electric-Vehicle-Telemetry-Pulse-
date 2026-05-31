// CI/CD Pipeline Tracking Test

// ============================================================
// EV-Pulse — Azure Infrastructure as Code (Bicep)
// Team    : 4DT Team 1
// 생성    : Azure Portal "템플릿 내보내기" 후 보안 처리 및 주석 추가
//
// [리전 고정 전략 — Explicit Location Locking]
//   - Azure OpenAI (GPT-4o-mini): 'eastus' 고정
//       → Korea Central은 gpt-4o-mini 미지원. 가용 모델 확보를 위해 고정.
//   - 실시간 데이터 파이프라인 (IoT Hub, Stream Analytics, SQL, Logic Apps): 'koreacentral' 고정
//       → 데이터 레이턴시 최소화 목적. 다른 리전 오배포 시 아키텍처 전체가 깨짐.
//   → 리전을 파라미터로 열어두지 않고 의도적으로 코드에 명시 고정(Explicit Locking).
//      휴먼 에러로 인한 오배포를 원천 차단하기 위한 설계 결정.
//
// [배포 방법]
//   az deployment group create \
//     --resource-group evpulse-rg \
//     --template-file template.bicep \
//     --parameters @parameters.json
// ============================================================

// ── 민감값 파라미터 (parameters.json에서 주입 — 코드에 직접 입력 금지) ──
@description('Azure AD Tenant ID — Key Vault 접근 제어에 사용')
@secure()
param tenantId string

@description('Key Vault 접근 권한을 부여할 사용자/서비스 주체의 Object ID')
@secure()
param keyVaultObjectId string

@description('Azure Subscription ID')
@secure()
param subscriptionId string

// ── 기존 파라미터 ────────────────────────────────────────────

@description('SQL Server Administrator Password')
@secure()
param sqlAdminPassword string
param connections_sql_name string = 'sql'
param connections_slack_name string = 'slack'
param sites_ev_pulse_chat_name string = 'ev-pulse-chat'
param IotHubs_evpulse_iothub_name string = 'evpulse-iothub'
param servers_sqlserver_4dt_team1_name string = 'sqlserver-4dt-team1'
param workflows_evpulse_logic_app_name string = 'evpulse-logic-app'
param serverfarms_ASP_4dtteam1_88e2_name string = 'ASP-4dtteam1-88e2'
param storageAccounts_4dtteam1af8e_name string = '4dtteam1af8e'
param vaults_evmodelingml9323514119_name string = 'evmodelingml9323514119'
param storageAccounts_4dtteam1storage_name string = '4dtteam1storage'
param accounts_evpulse_azoai_name string = 'evpulse-azoai'
param components_evmodelingml8998220664_name string = 'evmodelingml8998220664'
param storageAccounts_evmodelingml3270747925_name string = 'evmodelingml3270747925'
param workspaces_ev_modeling_ML_name string = 'ev-modeling-ML'
param workspaces_evmodelingml1303723571_name string = 'evmodelingml1303723571'
param registries_evmodelingml_name string = 'evmodelingmlcr'
param smartdetectoralertrules_failure_anomalies_evmodelingml8998220664_name string = 'failure anomalies - evmodelingml8998220664'
param actiongroups_application_insights_smart_detection_externalid string = '/subscriptions/${subscriptionId}/resourceGroups/a000-aml-rg/providers/microsoft.insights/actiongroups/application insights smart detection'

// ── 포털 CSV 기반 추가 리소스 파라미터 ─────────────────────────────
param storageAccounts_4dtteam19174_name string = '4dtteam19174'
param storageAccounts_evpulsestoragedev_name string = 'evpulsestoragedev'
param serverfarms_ASP_4dtteam1_9d0a_name string = 'ASP-4dtteam1-9d0a'
param sites_evpulse_report_function_name string = 'evpulse-report-function'
param components_evpulse_report_function_name string = 'evpulse-report-function'
param smartdetectoralertrules_failure_anomalies_evpulse_report_function_name string = 'Failure Anomalies - evpulse-report-function'
param managedIdentity_evpulse_azurebot_name string = 'evpulse-azurebot'
param botServices_evpulse_azurebot_name string = 'evpulse-azurebot'
param connections_teams_name string = 'teams'
param registries_dcb3bab8_name string = 'dcb3bab86b8249768958c307ec831b05'
param onlineEndpoints_ev_anomaly_6403dedf_name string = 'ev-anomaly-endpoint-6403dedf'


resource accounts_evpulse_azoai_name_resource 'Microsoft.CognitiveServices/accounts@2025-12-01' = {
  name: accounts_evpulse_azoai_name
  // [리전 고정] eastus — Korea Central은 gpt-4o-mini 미지원으로 인해 East US로 고정.
  // 다른 리전으로 배포 시 RAG 챗봇 전체가 동작하지 않으므로 파라미터로 열지 않음.
  location: 'eastus'
  sku: {
    name: 'S0'
  }
  kind: 'OpenAI'
  properties: {
    apiProperties: {}
    customSubDomainName: accounts_evpulse_azoai_name
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    allowProjectManagement: false
    publicNetworkAccess: 'Enabled'
    storedCompletionsDisabled: false
  }
}

resource IotHubs_evpulse_iothub_name_resource 'Microsoft.Devices/IotHubs@2025-08-01-preview' = {
  name: IotHubs_evpulse_iothub_name
  // [리전 고정] koreacentral — 실시간 데이터 파이프라인 레이턴시 최소화.
  // IoT Hub · Stream Analytics · SQL · Logic Apps 모두 동일 리전으로 묶어야
  // 리전 간 전송 지연 없이 동작함. 오배포 방지를 위해 파라미터로 열지 않음.
  location: 'koreacentral'
  sku: {
    name: 'S1'
    tier: 'Standard'
    capacity: 1
  }
  identity: {
    type: 'None'
  }
  properties: {
    ipFilterRules: []
    eventHubEndpoints: {
      events: {
        retentionTimeInDays: 1
        partitionCount: 2
      }
    }
    routing: {
      endpoints: {
        serviceBusQueues: []
        serviceBusTopics: []
        eventHubs: []
        storageContainers: []
        cosmosDBSqlContainers: []
      }
      routes: []
      fallbackRoute: {
        name: '$fallback'
        source: 'DeviceMessages'
        condition: 'true'
        endpointNames: [
          'events'
        ]
        isEnabled: true
      }
    }
    storageEndpoints: {}
    messagingEndpoints: {
      fileNotifications: {
        lockDurationAsIso8601: 'PT1M'
        ttlAsIso8601: 'PT1H'
        maxDeliveryCount: 10
      }
    }
    enableFileUploadNotifications: false
    cloudToDevice: {
      maxDeliveryCount: 10
      defaultTtlAsIso8601: 'PT1H'
      feedback: {
        lockDurationAsIso8601: 'PT1M'
        ttlAsIso8601: 'PT1H'
        maxDeliveryCount: 10
      }
    }
    features: 'RootCertificateV2'
    minTlsVersion: '1.2'
    disableLocalAuth: false
    allowedFqdnList: []
    enableDataResidency: false
    rootCertificate: {
      enableRootCertificateV2: true
    }
  }
}

resource vaults_evmodelingml9323514119_name_resource 'Microsoft.KeyVault/vaults@2026-03-01-preview' = {
  name: vaults_evmodelingml9323514119_name
  location: 'koreacentral'
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId                                 // 파라미터 참조 — 하드코딩 제거
    accessPolicies: [
      {
        tenantId: tenantId                             // 파라미터 참조
        objectId: keyVaultObjectId                     // 파라미터 참조 — 하드코딩 제거
        permissions: {
          keys: [
            'all'
          ]
          secrets: [
            'all'
          ]
          certificates: [
            'all'
          ]
          storage: []
        }
      }
    ]
    enabledForDeployment: false
    enableSoftDelete: true
    enableRbacAuthorization: false
    vaultUri: 'https://${vaults_evmodelingml9323514119_name}.vault.azure.net/'
    provisioningState: 'Succeeded'
    publicNetworkAccess: 'Enabled'
  }
}

resource workspaces_evmodelingml1303723571_name_resource 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: workspaces_evmodelingml1303723571_name
  location: 'koreacentral'
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      legacy: 0
      searchVersion: 1
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource servers_sqlserver_4dt_team1_name_resource 'Microsoft.Sql/servers@2025-02-01-preview' = {
  name: servers_sqlserver_4dt_team1_name
  location: 'koreacentral'
  kind: 'v12.0'
  properties: {
    administratorLogin: 'sqluser'
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Disabled'
    retentionDays: -1
  }
}

resource storageAccounts_4dtteam1af8e_name_resource 'Microsoft.Storage/storageAccounts@2025-08-01' = {
  name: storageAccounts_4dtteam1af8e_name
  location: 'koreacentral'
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  kind: 'StorageV2'
  properties: {
    defaultToOAuthAuthentication: true
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      ipv6Rules: []
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

resource storageAccounts_4dtteam1storage_name_resource 'Microsoft.Storage/storageAccounts@2025-08-01' = {
  name: storageAccounts_4dtteam1storage_name
  location: 'koreacentral'
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  kind: 'StorageV2'
  properties: {
    dualStackEndpointPreference: {
      publishIpv6Endpoint: false
    }
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      ipv6Rules: []
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

resource storageAccounts_evmodelingml3270747925_name_resource 'Microsoft.Storage/storageAccounts@2025-08-01' = {
  name: storageAccounts_evmodelingml3270747925_name
  location: 'koreacentral'
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  kind: 'StorageV2'
  properties: {
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    isHnsEnabled: false
    networkAcls: {
      ipv6Rules: []
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}


resource connections_sql_name_resource 'Microsoft.Web/connections@2016-06-01' = {
  name: connections_sql_name
  location: 'koreacentral'
  kind: 'V1'
  properties: {
    displayName: 'SQL-Connection-evpulse'
    statuses: [
      {
        status: 'Connected'
      }
    ]
    customParameterValues: {}
    createdTime: '2026-05-19T07:17:17.3049395Z'
    changedTime: '2026-05-19T07:17:17.3049395Z'
    api: {
      name: connections_sql_name
      displayName: 'SQL Server'
      description: 'Microsoft SQL Server is a relational database management system developed by Microsoft. Connect to SQL Server to manage data. You can perform various actions such as create, update, get, and delete on rows in a table.'
      iconUri: 'https://static.powerapps.com/resource/ppcr/releases/v1.0.1800/1.0.1800.4674/${connections_sql_name}/icon.png'
      brandColor: '#ba141a'
      id: '/subscriptions/${subscriptionId}/providers/Microsoft.Web/locations/koreacentral/managedApis/${connections_sql_name}'
      type: 'Microsoft.Web/locations/managedApis'
    }
    testLinks: [
      {
        requestUri: 'https://management.azure.com:443/subscriptions/${subscriptionId}/resourceGroups/4dt_team_1/providers/Microsoft.Web/connections/${connections_sql_name}/extensions/proxy/testconnection?api-version=2016-06-01'
        method: 'get'
      }
    ]
  }
}

resource connections_slack_name_resource 'Microsoft.Web/connections@2016-06-01' = {
  name: connections_slack_name
  location: 'koreacentral'
  kind: 'V1'
  properties: {
    displayName: 'EV-Pulse Slack Connection'
    statuses: [
      {
        status: 'Connected'
      }
    ]
    customParameterValues: {}
    nonSecretParameterValues: {}
    api: {
      name: connections_slack_name
      displayName: 'Slack'
      description: 'Slack is a messaging app for teams. Connect to Slack to manage messages and channels.'
      iconUri: 'https://static.powerapps.com/resource/ppcr/releases/v1.0.1812/1.0.1812.4744/${connections_slack_name}/icon.png'
      id: '/subscriptions/${subscriptionId}/providers/Microsoft.Web/locations/koreacentral/managedApis/${connections_slack_name}'
      type: 'Microsoft.Web/locations/managedApis'
    }
    testLinks: [
      {
        requestUri: 'https://management.azure.com:443/subscriptions/${subscriptionId}/resourceGroups/4dt_team_1/providers/Microsoft.Web/connections/${connections_slack_name}/extensions/proxy/testconnection?api-version=2016-06-01'
        method: 'get'
      }
    ]
  }
}

resource serverfarms_ASP_4dtteam1_88e2_name_resource 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: serverfarms_ASP_4dtteam1_88e2_name
  location: 'Korea Central'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
    size: 'FC1'
    family: 'FC'
    capacity: 0
  }
  kind: 'functionapp'
  properties: {
    perSiteScaling: false
    elasticScaleEnabled: false
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: true
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
    zoneRedundant: false
    asyncScalingEnabled: false
  }
}

resource accounts_evpulse_azoai_name_Default 'Microsoft.CognitiveServices/accounts/defenderForAISettings@2025-12-01' = {
  parent: accounts_evpulse_azoai_name_resource
  name: 'Default'
  properties: {
    state: 'Disabled'
  }
}

resource accounts_evpulse_azoai_name_evpulse_gpt 'Microsoft.CognitiveServices/accounts/deployments@2025-12-01' = {
  parent: accounts_evpulse_azoai_name_resource
  name: 'evpulse-gpt'
  sku: {
    name: 'GlobalStandard'
    capacity: 5
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o-mini'
      version: '2024-07-18'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    currentCapacity: 5
    raiPolicyName: 'Microsoft.DefaultV2'
    deploymentState: 'Running'
  }
}

resource components_evmodelingml8998220664_name_resource 'microsoft.insights/components@2020-02-02' = {
  name: components_evmodelingml8998220664_name
  location: 'koreacentral'
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'IbizaMachineLearningExtension'
    RetentionInDays: 90
    WorkspaceResourceId: workspaces_evmodelingml1303723571_name_resource.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource servers_sqlserver_4dt_team1_name_Default 'Microsoft.Sql/servers/advancedThreatProtectionSettings@2025-02-01-preview' = {
  parent: servers_sqlserver_4dt_team1_name_resource
  name: 'Default'
  properties: {
    state: 'Disabled'
  }
}

resource Microsoft_Sql_servers_auditingPolicies_servers_sqlserver_4dt_team1_name_Default 'Microsoft.Sql/servers/auditingPolicies@2014-04-01' = {
  parent: servers_sqlserver_4dt_team1_name_resource
  name: 'Default'
  location: 'Korea Central'
  properties: {
    auditingState: 'Disabled'
  }
}

resource Microsoft_Sql_servers_auditingSettings_servers_sqlserver_4dt_team1_name_Default 'Microsoft.Sql/servers/auditingSettings@2025-02-01-preview' = {
  parent: servers_sqlserver_4dt_team1_name_resource
  name: 'default'
  properties: {
    retentionDays: 0
    auditActionsAndGroups: []
    isStorageSecondaryKeyInUse: false
    isAzureMonitorTargetEnabled: false
    isManagedIdentityInUse: false
    state: 'Disabled'
    storageAccountSubscriptionId: '00000000-0000-0000-0000-000000000000'
  }
}

resource Microsoft_Sql_servers_connectionPolicies_servers_sqlserver_4dt_team1_name_default 'Microsoft.Sql/servers/connectionPolicies@2025-02-01-preview' = {
  parent: servers_sqlserver_4dt_team1_name_resource
  name: 'default'
  location: 'koreacentral'
  properties: {
    connectionType: 'Default'
  }
}

resource servers_sqlserver_4dt_team1_name_4dt_team1_DB 'Microsoft.Sql/servers/databases@2025-02-01-preview' = {
  parent: servers_sqlserver_4dt_team1_name_resource
  name: '4dt_team1_DB'
  location: 'koreacentral'
  sku: {
    name: 'GP_S_Gen5_2'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 2
  }
  kind: 'v12.0,user,vcore,serverless'
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 5368709120
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
    readScale: 'Disabled'
    autoPauseDelay: 60
    requestedBackupStorageRedundancy: 'Local'
    minCapacity: json('0.5')
    maintenanceConfigurationId: '/subscriptions/${subscriptionId}/providers/Microsoft.Maintenance/publicMaintenanceConfigurations/SQL_Default'
    isLedgerOn: false
    availabilityZone: 'NoPreference'
  }
}

resource servers_sqlserver_4dt_team1_name_master_Default 'Microsoft.Sql/servers/databases/advancedThreatProtectionSettings@2025-02-01-preview' = {
  name: '${servers_sqlserver_4dt_team1_name}/master/Default'
  properties: {
    state: 'Disabled'
  }
  dependsOn: [
    servers_sqlserver_4dt_team1_name_resource
  ]
}

resource Microsoft_Sql_servers_databases_auditingPolicies_servers_sqlserver_4dt_team1_name_master_Default 'Microsoft.Sql/servers/databases/auditingPolicies@2014-04-01' = {
  name: '${servers_sqlserver_4dt_team1_name}/master/Default'
  location: 'Korea Central'
  properties: {
    auditingState: 'Disabled'
  }
  dependsOn: [
    servers_sqlserver_4dt_team1_name_resource
  ]
}

resource Microsoft_Sql_servers_databases_auditingSettings_servers_sqlserver_4dt_team1_name_master_Default 'Microsoft.Sql/servers/databases/auditingSettings@2025-02-01-preview' = {
  name: '${servers_sqlserver_4dt_team1_name}/master/Default'
  properties: {
    retentionDays: 0
    isAzureMonitorTargetEnabled: false
    state: 'Disabled'
    storageAccountSubscriptionId: '00000000-0000-0000-0000-000000000000'
  }
  dependsOn: [
    servers_sqlserver_4dt_team1_name_resource
  ]
}

resource Microsoft_Sql_servers_databases_extendedAuditingSettings_servers_sqlserver_4dt_team1_name_master_Default 'Microsoft.Sql/servers/databases/extendedAuditingSettings@2025-02-01-preview' = {
  name: '${servers_sqlserver_4dt_team1_name}/master/Default'
  properties: {
    retentionDays: 0
    isAzureMonitorTargetEnabled: false
    state: 'Disabled'
    storageAccountSubscriptionId: '00000000-0000-0000-0000-000000000000'
  }
  dependsOn: [
    servers_sqlserver_4dt_team1_name_resource
  ]
}

resource Microsoft_Sql_servers_databases_geoBackupPolicies_servers_sqlserver_4dt_team1_name_master_Default 'Microsoft.Sql/servers/databases/geoBackupPolicies@2025-02-01-preview' = {
  name: '${servers_sqlserver_4dt_team1_name}/master/Default'
  properties: {
    state: 'Disabled'
  }
  dependsOn: [
    servers_sqlserver_4dt_team1_name_resource
  ]
}

resource Microsoft_Sql_servers_databases_securityAlertPolicies_servers_sqlserver_4dt_team1_name_master_Default 'Microsoft.Sql/servers/databases/securityAlertPolicies@2025-02-01-preview' = {
  name: '${servers_sqlserver_4dt_team1_name}/master/Default'
  properties: {
    state: 'Disabled'
    disabledAlerts: [
      ''
    ]
    emailAddresses: [
      ''
    ]
    emailAccountAdmins: false
    retentionDays: 0
  }
  dependsOn: [
    servers_sqlserver_4dt_team1_name_resource
  ]
}

resource Microsoft_Sql_servers_databases_transparentDataEncryption_servers_sqlserver_4dt_team1_name_master_Current 'Microsoft.Sql/servers/databases/transparentDataEncryption@2025-02-01-preview' = {
  name: '${servers_sqlserver_4dt_team1_name}/master/Current'
  properties: {
    state: 'Disabled'
  }
  dependsOn: [
    servers_sqlserver_4dt_team1_name_resource
  ]
}

resource Microsoft_Sql_servers_databases_vulnerabilityAssessments_servers_sqlserver_4dt_team1_name_master_Default 'Microsoft.Sql/servers/databases/vulnerabilityAssessments@2025-02-01-preview' = {
  name: '${servers_sqlserver_4dt_team1_name}/master/Default'
  properties: {
    recurringScans: {
      isEnabled: false
      emailSubscriptionAdmins: true
    }
  }
  dependsOn: [
    servers_sqlserver_4dt_team1_name_resource
  ]
}

resource Microsoft_Sql_servers_devOpsAuditingSettings_servers_sqlserver_4dt_team1_name_Default 'Microsoft.Sql/servers/devOpsAuditingSettings@2025-02-01-preview' = {
  parent: servers_sqlserver_4dt_team1_name_resource
  name: 'Default'
  properties: {
    isAzureMonitorTargetEnabled: false
    isManagedIdentityInUse: false
    state: 'Disabled'
    storageAccountSubscriptionId: '00000000-0000-0000-0000-000000000000'
  }
}

resource Microsoft_Sql_servers_extendedAuditingSettings_servers_sqlserver_4dt_team1_name_Default 'Microsoft.Sql/servers/extendedAuditingSettings@2025-02-01-preview' = {
  parent: servers_sqlserver_4dt_team1_name_resource
  name: 'default'
  properties: {
    retentionDays: 0
    auditActionsAndGroups: []
    isStorageSecondaryKeyInUse: false
    isAzureMonitorTargetEnabled: false
    isManagedIdentityInUse: false
    state: 'Disabled'
    storageAccountSubscriptionId: '00000000-0000-0000-0000-000000000000'
  }
}

resource servers_sqlserver_4dt_team1_name_AllowAllWindowsAzureIps 'Microsoft.Sql/servers/firewallRules@2025-02-01-preview' = {
  parent: servers_sqlserver_4dt_team1_name_resource
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// 개인 IP 방화벽 규칙 제거 — 필요 시 Azure Portal에서 직접 추가:
// SQL Server → 네트워킹 → 클라이언트 IP 추가

resource Microsoft_Sql_servers_securityAlertPolicies_servers_sqlserver_4dt_team1_name_Default 'Microsoft.Sql/servers/securityAlertPolicies@2025-02-01-preview' = {
  parent: servers_sqlserver_4dt_team1_name_resource
  name: 'Default'
  properties: {
    state: 'Disabled'
    disabledAlerts: [
      ''
    ]
    emailAddresses: [
      ''
    ]
    emailAccountAdmins: false
    retentionDays: 0
  }
}

resource Microsoft_Sql_servers_sqlVulnerabilityAssessments_servers_sqlserver_4dt_team1_name_Default 'Microsoft.Sql/servers/sqlVulnerabilityAssessments@2025-02-01-preview' = {
  parent: servers_sqlserver_4dt_team1_name_resource
  name: 'Default'
  properties: {
    state: 'Disabled'
  }
}


resource storageAccounts_4dtteam1af8e_name_default 'Microsoft.Storage/storageAccounts/blobServices@2025-08-01' = {
  parent: storageAccounts_4dtteam1af8e_name_resource
  name: 'default'
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  properties: {
    staticWebsite: {
      enabled: false
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: false
    }
  }
}

resource storageAccounts_4dtteam1storage_name_default 'Microsoft.Storage/storageAccounts/blobServices@2025-08-01' = {
  parent: storageAccounts_4dtteam1storage_name_resource
  name: 'default'
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  properties: {
    staticWebsite: {
      enabled: false
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: true
      days: 7
    }
  }
}

resource storageAccounts_evmodelingml3270747925_name_default 'Microsoft.Storage/storageAccounts/blobServices@2025-08-01' = {
  parent: storageAccounts_evmodelingml3270747925_name_resource
  name: 'default'
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  properties: {
    staticWebsite: {
      enabled: false
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: false
    }
  }
}

resource Microsoft_Storage_storageAccounts_fileServices_storageAccounts_4dtteam1af8e_name_default 'Microsoft.Storage/storageAccounts/fileServices@2025-08-01' = {
  parent: storageAccounts_4dtteam1af8e_name_resource
  name: 'default'
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  properties: {
    protocolSettings: {
      smb: {}
    }
    cors: {
      corsRules: []
    }
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource Microsoft_Storage_storageAccounts_fileServices_storageAccounts_4dtteam1storage_name_default 'Microsoft.Storage/storageAccounts/fileServices@2025-08-01' = {
  parent: storageAccounts_4dtteam1storage_name_resource
  name: 'default'
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  properties: {
    protocolSettings: {
      smb: {
        encryptionInTransit: {
          required: true
        }
      }
    }
    cors: {
      corsRules: []
    }
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource Microsoft_Storage_storageAccounts_fileServices_storageAccounts_evmodelingml3270747925_name_default 'Microsoft.Storage/storageAccounts/fileServices@2025-08-01' = {
  parent: storageAccounts_evmodelingml3270747925_name_resource
  name: 'default'
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  properties: {
    protocolSettings: {
      smb: {}
    }
    cors: {
      corsRules: []
    }
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource Microsoft_Storage_storageAccounts_queueServices_storageAccounts_4dtteam1af8e_name_default 'Microsoft.Storage/storageAccounts/queueServices@2025-08-01' = {
  parent: storageAccounts_4dtteam1af8e_name_resource
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

resource Microsoft_Storage_storageAccounts_queueServices_storageAccounts_4dtteam1storage_name_default 'Microsoft.Storage/storageAccounts/queueServices@2025-08-01' = {
  parent: storageAccounts_4dtteam1storage_name_resource
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

resource Microsoft_Storage_storageAccounts_queueServices_storageAccounts_evmodelingml3270747925_name_default 'Microsoft.Storage/storageAccounts/queueServices@2025-08-01' = {
  parent: storageAccounts_evmodelingml3270747925_name_resource
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

resource Microsoft_Storage_storageAccounts_tableServices_storageAccounts_4dtteam1af8e_name_default 'Microsoft.Storage/storageAccounts/tableServices@2025-08-01' = {
  parent: storageAccounts_4dtteam1af8e_name_resource
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

resource Microsoft_Storage_storageAccounts_tableServices_storageAccounts_4dtteam1storage_name_default 'Microsoft.Storage/storageAccounts/tableServices@2025-08-01' = {
  parent: storageAccounts_4dtteam1storage_name_resource
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

resource Microsoft_Storage_storageAccounts_tableServices_storageAccounts_evmodelingml3270747925_name_default 'Microsoft.Storage/storageAccounts/tableServices@2025-08-01' = {
  parent: storageAccounts_evmodelingml3270747925_name_resource
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

resource sites_ev_pulse_chat_name_ftp 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-11-01' = {
  parent: sites_ev_pulse_chat_name_resource
  name: 'ftp'
  location: 'Korea Central'
  properties: {
    allow: false
  }
}

resource sites_ev_pulse_chat_name_scm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-11-01' = {
  parent: sites_ev_pulse_chat_name_resource
  name: 'scm'
  location: 'Korea Central'
  properties: {
    allow: false
  }
}

resource sites_ev_pulse_chat_name_web 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: sites_ev_pulse_chat_name_resource
  name: 'web'
  location: 'Korea Central'
  properties: {
    numberOfWorkers: 1
    defaultDocuments: [
      'Default.htm'
      'Default.html'
      'Default.asp'
      'index.htm'
      'index.html'
      'iisstart.htm'
      'default.aspx'
      'index.php'
    ]
    netFrameworkVersion: 'v4.0'
    requestTracingEnabled: false
    remoteDebuggingEnabled: false
    httpLoggingEnabled: false
    acrUseManagedIdentityCreds: false
    logsDirectorySizeLimit: 35
    detailedErrorLoggingEnabled: false
    publishingUsername: 'REDACTED'
    scmType: 'None'
    use32BitWorkerProcess: false
    webSocketsEnabled: false
    alwaysOn: false
    managedPipelineMode: 'Integrated'
    virtualApplications: [
      {
        virtualPath: '/'
        physicalPath: 'site\\wwwroot'
        preloadEnabled: false
      }
    ]
    loadBalancing: 'LeastRequests'
    experiments: {
      rampUpRules: []
    }
    autoHealEnabled: false
    vnetRouteAllEnabled: false
    vnetPrivatePortsCount: 0
    publicNetworkAccess: 'Enabled'
    cors: {
      allowedOrigins: [
        'https://portal.azure.com'
      ]
      supportCredentials: false
    }
    localMySqlEnabled: false
    ipSecurityRestrictions: [
      {
        ipAddress: 'Any'
        action: 'Allow'
        priority: 2147483647
        name: 'Allow all'
        description: 'Allow all access'
      }
    ]
    scmIpSecurityRestrictions: [
      {
        ipAddress: 'Any'
        action: 'Allow'
        priority: 2147483647
        name: 'Allow all'
        description: 'Allow all access'
      }
    ]
    scmIpSecurityRestrictionsUseMain: false
    http20Enabled: false
    minTlsVersion: '1.2'
    scmMinTlsVersion: '1.2'
    ftpsState: 'FtpsOnly'
    preWarmedInstanceCount: 0
    functionAppScaleLimit: 100
    functionsRuntimeScaleMonitoringEnabled: false
    minimumElasticInstanceCount: 0
    azureStorageAccounts: {}
    http20ProxyFlag: 0
  }
}

resource sites_ev_pulse_chat_name_sites_ev_pulse_chat_name_f9fehsgrekeah7fx_koreacentral_01_azurewebsites_net 'Microsoft.Web/sites/hostNameBindings@2024-11-01' = {
  parent: sites_ev_pulse_chat_name_resource
  name: '${sites_ev_pulse_chat_name}-f9fehsgrekeah7fx.koreacentral-01.azurewebsites.net'
  location: 'Korea Central'
  properties: {
    siteName: 'ev-pulse-chat'
    hostNameType: 'Verified'
  }
}

resource workflows_evpulse_logic_app_name_resource 'Microsoft.Logic/workflows@2017-07-01' = {
  name: workflows_evpulse_logic_app_name
  location: 'koreacentral'
  properties: {
    state: 'Enabled'
    definition: {
      metadata: {
        notes: {}
      }
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        'When_an_item_is_created_(V2)': {
          recurrence: {
            interval: 3
            frequency: 'Minute'
          }
          evaluatedRecurrence: {
            interval: 3
            frequency: 'Minute'
          }
          splitOn: '@triggerBody()?[\'value\']'
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sql\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'default\'))},@{encodeURIComponent(encodeURIComponent(\'default\'))}/tables/@{encodeURIComponent(encodeURIComponent(\'[dbo].[ModelAlertTest]\'))}/onnewitems'
          }
        }
      }
      actions: {
        Condition: {
          actions: {
            'Slack_메시지_게시': {
              type: 'ApiConnection'
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'slack\'][\'connectionId\']'
                  }
                }
                method: 'post'
                body: {
                  text: '[@{triggerBody()?[\'alertStatus\']}]이 감지되었습니다.\nID : @{triggerBody()?[\'alertId\']}\nBSI 수치 : @{triggerBody()?[\'bsiValue\']}\n이상있는 피쳐 : @{triggerBody()?[\'triggeredFeature\']}\n감지 시간 : @{formatDateTime(addHours(triggerOutputs()?[\'body/timestamp\'], 9), \'yyyy년 MM월 dd일 HH시 mm분\')}'
                }
                path: '/chat.postMessage'
              }
            }
          }
          runAfter: {}
          else: {
            actions: {}
          }
          expression: {
            or: [
              {
                contains: [
                  '@triggerBody()?[\'alertStatus\']'
                  '이상'
                ]
              }
              {
                contains: [
                  '@triggerBody()?[\'alertStatus\']'
                  '위험'
                ]
              }
            ]
          }
          type: 'If'
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          sql: {
            id: '/subscriptions/${subscriptionId}/providers/Microsoft.Web/locations/koreacentral/managedApis/sql'
            connectionId: connections_sql_name_resource.id
            connectionName: 'sql'
            connectionProperties: {}
          }
          slack: {
            id: '/subscriptions/${subscriptionId}/providers/Microsoft.Web/locations/koreacentral/managedApis/slack'
            connectionId: connections_slack_name_resource.id
            connectionName: 'slack'
            connectionProperties: {}
          }
        }
      }
    }
  }
}

resource servers_sqlserver_4dt_team1_name_4dt_team1_DB_Default 'Microsoft.Sql/servers/databases/advancedThreatProtectionSettings@2025-02-01-preview' = {
  parent: servers_sqlserver_4dt_team1_name_4dt_team1_DB
  name: 'Default'
  properties: {
    state: 'Disabled'
  }
  dependsOn: [
    servers_sqlserver_4dt_team1_name_resource
  ]
}

resource Microsoft_Sql_servers_databases_auditingPolicies_servers_sqlserver_4dt_team1_name_4dt_team1_DB_Default 'Microsoft.Sql/servers/databases/auditingPolicies@2014-04-01' = {
  parent: servers_sqlserver_4dt_team1_name_4dt_team1_DB
  name: 'Default'
  location: 'Korea Central'
  properties: {
    auditingState: 'Disabled'
  }
  dependsOn: [
    servers_sqlserver_4dt_team1_name_resource
  ]
}

resource Microsoft_Sql_servers_databases_auditingSettings_servers_sqlserver_4dt_team1_name_4dt_team1_DB_Default 'Microsoft.Sql/servers/databases/auditingSettings@2025-02-01-preview' = {
  parent: servers_sqlserver_4dt_team1_name_4dt_team1_DB
  name: 'default'
  properties: {
    retentionDays: 0
    isAzureMonitorTargetEnabled: false
    state: 'Disabled'
    storageAccountSubscriptionId: '00000000-0000-0000-0000-000000000000'
  }
  dependsOn: [
    servers_sqlserver_4dt_team1_name_resource
  ]
}

resource Microsoft_Sql_servers_databases_backupLongTermRetentionPolicies_servers_sqlserver_4dt_team1_name_4dt_team1_DB_default 'Microsoft.Sql/servers/databases/backupLongTermRetentionPolicies@2025-02-01-preview' = {
  parent: servers_sqlserver_4dt_team1_name_4dt_team1_DB
  name: 'default'
  properties: {
    timeBasedImmutability: 'Disabled'
    weeklyRetention: 'PT0S'
    monthlyRetention: 'PT0S'
    yearlyRetention: 'PT0S'
    weekOfYear: 1
  }
  dependsOn: [
    servers_sqlserver_4dt_team1_name_resource
  ]
}

resource Microsoft_Sql_servers_databases_backupShortTermRetentionPolicies_servers_sqlserver_4dt_team1_name_4dt_team1_DB_default 'Microsoft.Sql/servers/databases/backupShortTermRetentionPolicies@2025-02-01-preview' = {
  parent: servers_sqlserver_4dt_team1_name_4dt_team1_DB
  name: 'default'
  properties: {
    retentionDays: 7
    diffBackupIntervalInHours: 12
  }
  dependsOn: [
    servers_sqlserver_4dt_team1_name_resource
  ]
}

resource Microsoft_Sql_servers_databases_extendedAuditingSettings_servers_sqlserver_4dt_team1_name_4dt_team1_DB_Default 'Microsoft.Sql/servers/databases/extendedAuditingSettings@2025-02-01-preview' = {
  parent: servers_sqlserver_4dt_team1_name_4dt_team1_DB
  name: 'default'
  properties: {
    retentionDays: 0
    isAzureMonitorTargetEnabled: false
    state: 'Disabled'
    storageAccountSubscriptionId: '00000000-0000-0000-0000-000000000000'
  }
  dependsOn: [
    servers_sqlserver_4dt_team1_name_resource
  ]
}

resource Microsoft_Sql_servers_databases_geoBackupPolicies_servers_sqlserver_4dt_team1_name_4dt_team1_DB_Default 'Microsoft.Sql/servers/databases/geoBackupPolicies@2025-02-01-preview' = {
  parent: servers_sqlserver_4dt_team1_name_4dt_team1_DB
  name: 'Default'
  properties: {
    state: 'Disabled'
  }
  dependsOn: [
    servers_sqlserver_4dt_team1_name_resource
  ]
}

resource Microsoft_Sql_servers_databases_securityAlertPolicies_servers_sqlserver_4dt_team1_name_4dt_team1_DB_Default 'Microsoft.Sql/servers/databases/securityAlertPolicies@2025-02-01-preview' = {
  parent: servers_sqlserver_4dt_team1_name_4dt_team1_DB
  name: 'Default'
  properties: {
    state: 'Disabled'
    disabledAlerts: [
      ''
    ]
    emailAddresses: [
      ''
    ]
    emailAccountAdmins: false
    retentionDays: 0
  }
  dependsOn: [
    servers_sqlserver_4dt_team1_name_resource
  ]
}

resource Microsoft_Sql_servers_databases_vulnerabilityAssessments_servers_sqlserver_4dt_team1_name_4dt_team1_DB_Default 'Microsoft.Sql/servers/databases/vulnerabilityAssessments@2025-02-01-preview' = {
  parent: servers_sqlserver_4dt_team1_name_4dt_team1_DB
  name: 'Default'
  properties: {
    recurringScans: {
      isEnabled: false
      emailSubscriptionAdmins: true
    }
  }
  dependsOn: [
    servers_sqlserver_4dt_team1_name_resource
  ]
}

resource storageAccounts_4dtteam1af8e_name_default_app_package_ev_pulse_chat_712edbe 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-08-01' = {
  parent: storageAccounts_4dtteam1af8e_name_default
  name: 'app-package-ev-pulse-chat-712edbe'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccounts_4dtteam1af8e_name_resource
  ]
}

resource storageAccounts_evmodelingml3270747925_name_default_azureml 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-08-01' = {
  parent: storageAccounts_evmodelingml3270747925_name_default
  name: 'azureml'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccounts_evmodelingml3270747925_name_resource
  ]
}

resource storageAccounts_evmodelingml3270747925_name_default_azureml_blobstore_dcb3bab8_6b82_4976_8958_c307ec831b05 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-08-01' = {
  parent: storageAccounts_evmodelingml3270747925_name_default
  name: 'azureml-blobstore-dcb3bab8-6b82-4976-8958-c307ec831b05'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccounts_evmodelingml3270747925_name_resource
  ]
}

resource storageAccounts_4dtteam1af8e_name_default_azure_webjobs_hosts 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-08-01' = {
  parent: storageAccounts_4dtteam1af8e_name_default
  name: 'azure-webjobs-hosts'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccounts_4dtteam1af8e_name_resource
  ]
}

resource storageAccounts_4dtteam1af8e_name_default_azure_webjobs_secrets 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-08-01' = {
  parent: storageAccounts_4dtteam1af8e_name_default
  name: 'azure-webjobs-secrets'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccounts_4dtteam1af8e_name_resource
  ]
}

resource storageAccounts_4dtteam1storage_name_default_bmw_originaldata 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-08-01' = {
  parent: storageAccounts_4dtteam1storage_name_default
  name: 'bmw-originaldata'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccounts_4dtteam1storage_name_resource
  ]
}

resource storageAccounts_evmodelingml3270747925_name_default_insights_logs_auditevent 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-08-01' = {
  parent: storageAccounts_evmodelingml3270747925_name_default
  name: 'insights-logs-auditevent'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccounts_evmodelingml3270747925_name_resource
  ]
}

resource storageAccounts_evmodelingml3270747925_name_default_insights_metrics_pt1m 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-08-01' = {
  parent: storageAccounts_evmodelingml3270747925_name_default
  name: 'insights-metrics-pt1m'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccounts_evmodelingml3270747925_name_resource
  ]
}

resource storageAccounts_4dtteam1storage_name_default_bmw_preprocessing 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-08-01' = {
  parent: storageAccounts_4dtteam1storage_name_default
  name: 'bmw-preprocessing'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccounts_4dtteam1storage_name_resource
  ]
}

resource storageAccounts_4dtteam1storage_name_default_nasa_battery_dataset 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-08-01' = {
  parent: storageAccounts_4dtteam1storage_name_default
  name: 'nasa-battery-dataset'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccounts_4dtteam1storage_name_resource
  ]
}

resource storageAccounts_evmodelingml3270747925_name_default_azureml_filestore_dcb3bab8_6b82_4976_8958_c307ec831b05 'Microsoft.Storage/storageAccounts/fileServices/shares@2025-08-01' = {
  parent: Microsoft_Storage_storageAccounts_fileServices_storageAccounts_evmodelingml3270747925_name_default
  name: 'azureml-filestore-dcb3bab8-6b82-4976-8958-c307ec831b05'
  properties: {
    accessTier: 'TransactionOptimized'
    shareQuota: 102400
    enabledProtocols: 'SMB'
  }
  dependsOn: [
    storageAccounts_evmodelingml3270747925_name_resource
  ]
}

resource storageAccounts_evmodelingml3270747925_name_default_code_391ff5ac_6576_460f_ba4d_7e03433c68b6 'Microsoft.Storage/storageAccounts/fileServices/shares@2025-08-01' = {
  parent: Microsoft_Storage_storageAccounts_fileServices_storageAccounts_evmodelingml3270747925_name_default
  name: 'code-391ff5ac-6576-460f-ba4d-7e03433c68b6'
  properties: {
    accessTier: 'TransactionOptimized'
    shareQuota: 102400
    enabledProtocols: 'SMB'
  }
  dependsOn: [
    storageAccounts_evmodelingml3270747925_name_resource
  ]
}

resource sites_ev_pulse_chat_name_resource 'Microsoft.Web/sites@2024-11-01' = {
  name: sites_ev_pulse_chat_name
  location: 'Korea Central'
  kind: 'functionapp,linux'
  properties: {
    enabled: true
    hostNameSslStates: [
      {
        name: '${sites_ev_pulse_chat_name}-f9fehsgrekeah7fx.koreacentral-01.azurewebsites.net'
        sslState: 'Disabled'
        hostType: 'Standard'
      }
      {
        name: '${sites_ev_pulse_chat_name}-f9fehsgrekeah7fx.scm.koreacentral-01.azurewebsites.net'
        sslState: 'Disabled'
        hostType: 'Repository'
      }
    ]
    serverFarmId: serverfarms_ASP_4dtteam1_88e2_name_resource.id
    reserved: true
    isXenon: false
    hyperV: false
    dnsConfiguration: {}
    outboundVnetRouting: {
      allTraffic: false
      applicationTraffic: false
      contentShareTraffic: false
      imagePullTraffic: false
      backupRestoreTraffic: false
    }
    siteConfig: {
      numberOfWorkers: 1
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
      functionAppScaleLimit: 100
      minimumElasticInstanceCount: 0
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: 'https://${storageAccounts_4dtteam1af8e_name}.blob.core.windows.net/app-package-${sites_ev_pulse_chat_name}-712edbe'
          authentication: {
            type: 'StorageAccountConnectionString'
            storageAccountConnectionStringName: 'DEPLOYMENT_STORAGE_CONNECTION_STRING'
          }
        }
      }
      runtime: {
        name: 'python'
        version: '3.11'
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 100
        instanceMemoryMB: 512
      }
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientAffinityProxyEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    ipMode: 'IPv4'
    // customDomainVerificationId — Azure 배포 시 자동 할당, 코드에 포함하지 않음
    containerSize: 1536
    dailyMemoryTimeQuota: 0
    httpsOnly: true
    endToEndEncryptionEnabled: false
    redundancyMode: 'None'
    publicNetworkAccess: 'Enabled'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
    autoGeneratedDomainNameLabelScope: 'TenantReuse'
  }
  dependsOn: [
    storageAccounts_4dtteam1af8e_name_resource
  ]
}

resource registries_evmodelingml_name_resource 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registries_evmodelingml_name
  location: 'koreacentral'
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
}

resource workspaces_ev_modeling_ML_name_resource 'Microsoft.MachineLearningServices/workspaces@2025-12-01' = {
  name: workspaces_ev_modeling_ML_name
  location: 'koreacentral'
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  kind: 'Default'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: workspaces_ev_modeling_ML_name
    storageAccount: storageAccounts_evmodelingml3270747925_name_resource.id
    keyVault: vaults_evmodelingml9323514119_name_resource.id
    applicationInsights: components_evmodelingml8998220664_name_resource.id
    containerRegistry: registries_evmodelingml_name_resource.id
    hbiWorkspace: false
    managedNetwork: {
      isolationMode: 'Disabled'
      enableNetworkMonitor: false
      managedNetworkKind: 'V1'
    }
    v1LegacyMode: false
    publicNetworkAccess: 'Enabled'
    discoveryUrl: 'https://koreacentral.api.azureml.ms/discovery'
    enableDataIsolation: false
    systemDatastoresAuthMode: 'accesskey'
    enableServiceSideCMKEncryption: false
    provisionNetworkNow: false
  }
}

// ════════════════════════════════════════════════════════════════
// 포털 CSV 기반 추가 리소스 (초기 Export에 미포함)
// ════════════════════════════════════════════════════════════════

// ── Storage: 4dtteam19174 (evpulse-report-function 런타임 스토리지) ──
resource storageAccounts_4dtteam19174_name_resource 'Microsoft.Storage/storageAccounts@2025-08-01' = {
  name: storageAccounts_4dtteam19174_name
  location: 'koreacentral'
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  kind: 'StorageV2'
  properties: {
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

// ── Storage: evpulsestoragedev (개발 환경 데이터 스토리지) ──
resource storageAccounts_evpulsestoragedev_name_resource 'Microsoft.Storage/storageAccounts@2025-08-01' = {
  name: storageAccounts_evpulsestoragedev_name
  location: 'koreacentral'
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  kind: 'StorageV2'
  properties: {
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

// ── App Service Plan: ASP-4dtteam1-9d0a (evpulse-report-function용 FlexConsumption) ──
resource serverfarms_ASP_4dtteam1_9d0a_name_resource 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: serverfarms_ASP_4dtteam1_9d0a_name
  location: 'Korea Central'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
    size: 'FC1'
    family: 'FC'
    capacity: 0
  }
  kind: 'functionapp'
  properties: {
    perSiteScaling: false
    elasticScaleEnabled: false
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: true
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
    zoneRedundant: false
    asyncScalingEnabled: false
  }
}

// ── Application Insights: evpulse-report-function ──
resource components_evpulse_report_function_name_resource 'microsoft.insights/components@2020-02-02' = {
  name: components_evpulse_report_function_name
  location: 'koreacentral'
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'IbizaWebAppExtensionCreate'
    RetentionInDays: 90
    WorkspaceResourceId: workspaces_evmodelingml1303723571_name_resource.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ── Function App: evpulse-report-function (보고서 생성 함수) ──
resource sites_evpulse_report_function_name_resource 'Microsoft.Web/sites@2024-11-01' = {
  name: sites_evpulse_report_function_name
  location: 'Korea Central'
  kind: 'functionapp,linux'
  properties: {
    enabled: true
    serverFarmId: serverfarms_ASP_4dtteam1_9d0a_name_resource.id
    reserved: true
    isXenon: false
    hyperV: false
    dnsConfiguration: {}
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: 'Python|3.11'
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    httpsOnly: true
    redundancyMode: 'None'
    publicNetworkAccess: 'Enabled'
    storageAccountRequired: false
  }
  dependsOn: [
    storageAccounts_4dtteam19174_name_resource
  ]
}

// ── Smart Detector Alert Rule: Failure Anomalies - evpulse-report-function ──
// [주의] actionGroups 제거 — SP가 a000-aml-rg의 action group 읽기 권한 없음
resource smartdetectoralertrules_evpulse_report_function_name_resource 'microsoft.alertsmanagement/smartDetectorAlertRules@2021-04-01' = {
  name: smartdetectoralertrules_failure_anomalies_evpulse_report_function_name
  location: 'global'
  properties: {
    description: 'Failure Anomalies notifies you of an unusual rise in the rate of failed HTTP requests or dependency calls.'
    state: 'Enabled'
    severity: 'Sev3'
    frequency: 'PT1M'
    detector: {
      id: 'FailureAnomaliesDetector'
    }
    scope: [
      components_evpulse_report_function_name_resource.id
    ]
    actionGroups: {
      groupIds: []
    }
  }
}

// ── Managed Identity: evpulse-azurebot (Bot Service MSI 인증용) ──
resource managedIdentity_evpulse_azurebot_name_resource 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentity_evpulse_azurebot_name
  location: 'koreacentral'
}

// ── Azure Bot: evpulse-azurebot (Text-to-SQL 챗봇)
// [리전 고정] global — Bot Service는 글로벌 서비스
// Text-to-SQL 흐름: 자연어 질의 → Azure OpenAI (evpulse-azoai) → SQL 생성 → 4dt_team1_DB 조회
resource botServices_evpulse_azurebot_name_resource 'Microsoft.BotService/botServices@2022-09-15' = {
  name: botServices_evpulse_azurebot_name
  location: 'global'
  sku: {
    name: 'F0'
  }
  kind: 'azurebot'
  properties: {
    displayName: botServices_evpulse_azurebot_name
    iconUrl: 'https://docs.botframework.com/static/devportal/client/images/bot-framework-default.png'
    msaAppType: 'UserAssignedMSI'
    msaAppId: managedIdentity_evpulse_azurebot_name_resource.properties.clientId
    msaAppTenantId: tenantId
    msaAppMSIResourceId: managedIdentity_evpulse_azurebot_name_resource.id
    isCmekEnabled: false
    publicNetworkAccess: 'Enabled'
    isStreamingSupported: false
  }
}

// ── API Connection: teams (Logic App → Teams 채널 알림) ──
resource connections_teams_name_resource 'Microsoft.Web/connections@2016-06-01' = {
  name: connections_teams_name
  location: 'koreacentral'
  kind: 'V1'
  properties: {
    displayName: 'EV-Pulse Teams Connection'
    statuses: [
      {
        status: 'Connected'
      }
    ]
    customParameterValues: {}
    nonSecretParameterValues: {}
    api: {
      name: connections_teams_name
      displayName: 'Microsoft Teams'
      description: 'Microsoft Teams enables you to get all your content, tools and conversations in the Team workspace with Office 365.'
      iconUri: 'https://connectoricons-prod.azureedge.net/releases/v1.0.1666/1.0.1666.3495/teams/icon.png'
      id: '/subscriptions/${subscriptionId}/providers/Microsoft.Web/locations/koreacentral/managedApis/${connections_teams_name}'
      type: 'Microsoft.Web/locations/managedApis'
    }
    testLinks: [
      {
        requestUri: 'https://management.azure.com:443/subscriptions/${subscriptionId}/resourceGroups/4dt_team_1/providers/Microsoft.Web/connections/${connections_teams_name}/extensions/proxy/testconnection?api-version=2016-06-01'
        method: 'get'
      }
    ]
  }
}

// ── Container Registry: dcb3bab86b8249768958c307ec831b05 (AML 보조 레지스트리) ──
resource registries_dcb3bab8_name_resource 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registries_dcb3bab8_name
  location: 'koreacentral'
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
}

// ── ML Online Endpoint: ev-anomaly-endpoint-6403dedf (purple2 — 최종 프로덕션 모델) ──
resource onlineEndpoints_ev_anomaly_6403dedf_name_resource 'Microsoft.MachineLearningServices/workspaces/onlineEndpoints@2025-12-01' = {
  parent: workspaces_ev_modeling_ML_name_resource
  name: onlineEndpoints_ev_anomaly_6403dedf_name
  location: 'koreacentral'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    authMode: 'Key'
    publicNetworkAccess: 'Enabled'
    description: 'EV 배터리 이상 탐지 모델 엔드포인트 (purple2 배포)'
  }
}

// ML Online Deployment: purple2
// [설계 결정] deployment 리소스는 Bicep에서 관리하지 않음
// → 모델 버전·환경·compute 설정이 복잡하여 AML Studio 또는 CLI로 별도 관리
// → az ml online-deployment create --file purple2-deployment.yml
//    (AML Studio에서 이미 배포 완료된 상태)
