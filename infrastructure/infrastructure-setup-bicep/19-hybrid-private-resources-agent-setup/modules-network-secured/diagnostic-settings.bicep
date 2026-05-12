/*
Diagnostic Settings Module
---------------------------
Wires Azure Diagnostic Settings from the workload-plane resources (App Gateway,
APIM, Bot Service, Foundry account) into the deployed Log Analytics Workspace.

This is what populates the KQL tables referenced in `docs/teams-app-debugging.md`:
  AzureDiagnostics (BotRequest)
  AGWAccessLogs / AGWFirewallLogs / AGWPerformanceLogs
  ApiManagementGatewayLogs / ApiManagementWebSocketConnectionLogs
  AzureDiagnostics (Cognitive Services RequestResponse / Audit)

All sub-resources are conditional — the module checks for non-empty name params
before declaring the diagnostic-setting child resource. Pass only the names you
actually deployed.

NOTE: All resources use Log Analytics as the destination. We DO NOT add a
storage account destination because deploymentScripts/storage policies often
block shared-key auth and add no value for a Log-Analytics-backed workflow.
*/

@description('Log Analytics Workspace resource ID (output from application-insights.bicep).')
param logAnalyticsWorkspaceId string

@description('Name of the Application Gateway to wire diagnostics on. Empty = skip.')
param applicationGatewayName string = ''

@description('Name of the API Management service to wire diagnostics on. Empty = skip.')
param apiManagementName string = ''

@description('Name of the Bot Service to wire diagnostics on. Empty = skip.')
param botServiceName string = ''

@description('Name of the AI Foundry / Cognitive Services account to wire diagnostics on. Empty = skip.')
param cognitiveServicesAccountName string = ''

// ----- Application Gateway -----
resource appGw 'Microsoft.Network/applicationGateways@2024-05-01' existing = if (!empty(applicationGatewayName)) {
  name: applicationGatewayName
}

resource appGwDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(applicationGatewayName)) {
  scope: appGw
  name: 'to-law'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ----- API Management -----
resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = if (!empty(apiManagementName)) {
  name: apiManagementName
}

resource apimDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(apiManagementName)) {
  scope: apim
  name: 'to-law'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ----- Bot Service -----
// Bot Service is 'global' scope on ARM, but diagnostic settings reference is fine
resource botService 'Microsoft.BotService/botServices@2023-09-15-preview' existing = if (!empty(botServiceName)) {
  name: botServiceName
}

resource botDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(botServiceName)) {
  scope: botService
  name: 'to-law'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'BotRequest'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ----- Foundry / Cognitive Services account -----
resource csAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = if (!empty(cognitiveServicesAccountName)) {
  name: cognitiveServicesAccountName
}

resource csDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(cognitiveServicesAccountName)) {
  scope: csAccount
  name: 'to-law'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ----- APIM API-level Application Insights logger (per-API tracing) -----
// Only wired when both APIM and the App Insights resource id are provided.
// Uses resourceId-only logger (no instrumentation-key secret required).

@description('Application Insights resource ID. When provided alongside apiManagementName, an APIM logger pointing at this App Insights is created so the bot-messaging API can be traced per-request.')
param applicationInsightsId string = ''

@description('Application Insights instrumentation key. Required by APIM logger API when applicationInsightsId is set.')
@secure()
param applicationInsightsInstrumentationKey string = ''

resource apimAppInsightsLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = if (!empty(apiManagementName) && !empty(applicationInsightsId) && !empty(applicationInsightsInstrumentationKey)) {
  parent: apim
  name: 'applicationinsights'
  properties: {
    loggerType: 'applicationInsights'
    description: 'Application Insights logger for bot-messaging API tracing'
    resourceId: applicationInsightsId
    credentials: {
      instrumentationKey: applicationInsightsInstrumentationKey
    }
  }
}

@description('Name of the APIM API to attach App Insights tracing to (e.g., bot-messaging). Empty = skip.')
param apimApiId string = ''

resource apimApi 'Microsoft.ApiManagement/service/apis@2024-05-01' existing = if (!empty(apiManagementName) && !empty(apimApiId)) {
  parent: apim
  name: apimApiId
}

resource apimApiDiag 'Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01' = if (!empty(apiManagementName) && !empty(applicationInsightsId) && !empty(apimApiId)) {
  parent: apimApi
  name: 'applicationinsights'
  properties: {
    alwaysLog: 'allErrors'
    loggerId: apimAppInsightsLogger.id
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    logClientIp: true
    httpCorrelationProtocol: 'W3C'
    verbosity: 'information'
  }
}
