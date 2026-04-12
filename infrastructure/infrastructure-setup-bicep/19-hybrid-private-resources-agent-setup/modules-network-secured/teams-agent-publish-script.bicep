/*
Teams Agent Publish Script Module
-----------------------------------
Deployment script that creates the Agent Application and Managed Deployment
for the workflow, then outputs the Activity Protocol URL needed by the
Bot Service messaging endpoint.

This handles the data plane operations that can't be expressed as ARM resources.
*/

@description('Azure region')
param location string

@description('Name of the AI Foundry account')
param accountName string

@description('Name of the project')
param projectName string

@description('Name of the agent to publish')
param agentName string

@description('Version of the agent to publish (empty = latest)')
param agentVersion string = ''

@description('Name for the Agent Application')
param applicationName string

@description('Name for the deployment')
param deploymentName string = 'teams-deployment'

// Script identity
resource scriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${applicationName}-publish-identity'
  location: location
}

// Grant Contributor on the RG for application publishing
resource scriptContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, scriptIdentity.id, 'contributor-teams-publish')
  properties: {
    principalId: scriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  }
}

// Grant AI Developer on the account
resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName
}

resource scriptAiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(account.id, scriptIdentity.id, 'ai-developer-teams-publish')
  scope: account
  properties: {
    principalId: scriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '64702f94-c441-49e6-a78b-ef80e0188fee')
  }
}

resource publishScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${applicationName}-publish-script'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${scriptIdentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '12.0'
    retentionInterval: 'PT1H'
    timeout: 'PT10M'
    environmentVariables: [
      { name: 'ACCOUNT_NAME', value: accountName }
      { name: 'PROJECT_NAME', value: projectName }
      { name: 'AGENT_NAME', value: agentName }
      { name: 'AGENT_VERSION', value: agentVersion }
      { name: 'APP_NAME', value: applicationName }
      { name: 'DEPLOY_NAME', value: deploymentName }
      { name: 'SUBSCRIPTION_ID', value: subscription().subscriptionId }
      { name: 'RESOURCE_GROUP', value: resourceGroup().name }
    ]
    scriptContent: '''
      $ErrorActionPreference = 'Stop'

      $armBase = "https://management.azure.com/subscriptions/$($env:SUBSCRIPTION_ID)/resourceGroups/$($env:RESOURCE_GROUP)/providers/Microsoft.CognitiveServices/accounts/$($env:ACCOUNT_NAME)/projects/$($env:PROJECT_NAME)"

      # Get ARM token
      $armToken = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token
      $armHeaders = @{
        "Authorization" = "Bearer $armToken"
        "Content-Type" = "application/json"
      }

      # Resolve agent version if not specified
      $agentVersion = $env:AGENT_VERSION
      if ([string]::IsNullOrEmpty($agentVersion)) {
        $aiToken = (Get-AzAccessToken -ResourceUrl "https://ai.azure.com").Token
        $aiHeaders = @{ "Authorization" = "Bearer $aiToken"; "Content-Type" = "application/json" }
        $baseUrl = "https://$($env:ACCOUNT_NAME).services.ai.azure.com/api/projects/$($env:PROJECT_NAME)"
        $versions = Invoke-RestMethod -Uri "$baseUrl/agents/$($env:AGENT_NAME)/versions?api-version=v1" -Headers $aiHeaders
        $agentVersion = $versions.data[0].version
        Write-Host "Resolved latest agent version: $agentVersion"
      }

      # Create Agent Application
      $appBody = @{
        properties = @{
          agents = @(@{ agentName = $env:AGENT_NAME })
          displayName = "$($env:APP_NAME)"
          description = "Published agent for Teams integration"
        }
      } | ConvertTo-Json -Depth 5
      try {
        $appResult = Invoke-RestMethod -Uri "$armBase/applications/$($env:APP_NAME)?api-version=2026-01-15-preview" -Method Put -Headers $armHeaders -Body $appBody
        Write-Host "Created application: $($env:APP_NAME)"
      } catch {
        Write-Host "Application may already exist, continuing..."
      }

      # Create Managed Deployment
      $deployBody = @{
        properties = @{
          displayName = "Teams Deployment"
          deploymentType = "Managed"
          protocols = @(
            @{ protocol = "Responses"; version = "1.0" }
            @{ protocol = "ActivityProtocol"; version = "1.0" }
          )
          agents = @(@{ agentName = $env:AGENT_NAME; agentVersion = "$agentVersion" })
        }
      } | ConvertTo-Json -Depth 5
      try {
        $deployResult = Invoke-RestMethod -Uri "$armBase/applications/$($env:APP_NAME)/agentdeployments/$($env:DEPLOY_NAME)?api-version=2026-01-15-preview" -Method Put -Headers $armHeaders -Body $deployBody
        Write-Host "Created deployment: $($env:DEPLOY_NAME)"
      } catch {
        Write-Host "Deployment may already exist, continuing..."
      }

      # Get the application details for the Activity Protocol URL
      $app = Invoke-RestMethod -Uri "$armBase/applications/$($env:APP_NAME)?api-version=2026-01-15-preview" -Method Get -Headers $armHeaders
      $baseUrl = $app.properties.baseUrl
      $activityUrl = "$baseUrl/protocols/activityprotocol"
      $botClientId = $app.properties.defaultInstanceIdentity.clientId

      Write-Host "Activity Protocol URL: $activityUrl"
      Write-Host "Bot Client ID: $botClientId"

      $DeploymentScriptOutputs = @{
        activityProtocolUrl = $activityUrl
        applicationBaseUrl = $baseUrl
        botClientId = $botClientId
        agentVersion = "$agentVersion"
      }
    '''
  }
  dependsOn: [
    scriptContributorRole
    scriptAiRole
  ]
}

output activityProtocolUrl string = publishScript.properties.outputs.activityProtocolUrl
output applicationBaseUrl string = publishScript.properties.outputs.applicationBaseUrl
output botClientId string = publishScript.properties.outputs.botClientId
output agentVersion string = publishScript.properties.outputs.agentVersion
