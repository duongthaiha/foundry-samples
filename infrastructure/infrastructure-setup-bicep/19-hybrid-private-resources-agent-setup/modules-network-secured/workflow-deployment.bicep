/*
Workflow Deployment Script Module
----------------------------------
Creates prompt agents and a sequential workflow using a Bicep deployment script.

Workflows and agents are data plane operations (not ARM resources), so they use
a deploymentScript to call the Foundry Agent API during deployment.

This creates:
  1. Three prompt agents (marketing-analyst, marketing-copywriter, marketing-editor)
  2. A sequential workflow agent (marketing-pipeline) that chains them
  3. An Agent Application + Deployment to publish the workflow
*/

@description('Azure region')
param location string

@description('Name of the AI Foundry account')
param accountName string

@description('Name of the project')
param projectName string

@description('Model to use for the agents (e.g., apim-gateway/gpt-4o-mini or gpt-4o-mini)')
param agentModel string

@description('Name for the workflow')
param workflowName string = 'marketing-pipeline'

@description('Name for the published application')
param applicationName string = 'marketing-pipeline-app'

@description('Name for the deployment')
param deploymentName string = 'marketing-pipeline-deployment'

// Reference existing resources for identity
resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName
}

// Deployment script uses system-assigned managed identity
// The identity needs Azure AI User role on the project
resource scriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${workflowName}-script-identity'
  location: location
}

// Grant the script identity Azure AI User role on the account
resource scriptRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(account.id, scriptIdentity.id, 'a]97b-65b7-4e0b-9910-1c2e2f5e5e5e')
  scope: account
  properties: {
    principalId: scriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    // Azure AI Developer role
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '64702f94-c441-49e6-a78b-ef80e0188fee')
  }
}

// Also grant Contributor on the RG for application publishing
resource scriptContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, scriptIdentity.id, 'contributor-workflow')
  properties: {
    principalId: scriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  }
}

resource workflowScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${workflowName}-deploy-script'
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
      { name: 'AGENT_MODEL', value: agentModel }
      { name: 'WORKFLOW_NAME', value: workflowName }
      { name: 'APP_NAME', value: applicationName }
      { name: 'DEPLOY_NAME', value: deploymentName }
      { name: 'SUBSCRIPTION_ID', value: subscription().subscriptionId }
      { name: 'RESOURCE_GROUP', value: resourceGroup().name }
    ]
    scriptContent: '''
      $ErrorActionPreference = 'Stop'

      # Get token for Foundry API
      $token = (Get-AzAccessToken -ResourceUrl "https://ai.azure.com").Token
      $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
      }
      $baseUrl = "https://$($env:ACCOUNT_NAME).services.ai.azure.com/api/projects/$($env:PROJECT_NAME)"

      # Create the 3 prompt agents
      $agents = @(
        @{
          name = "marketing-analyst"
          instructions = "You are a marketing analyst. Given a product description, identify: 1. Key features 2. Target audience 3. Unique selling points. Output as a structured list."
        },
        @{
          name = "marketing-copywriter"
          instructions = "You are a marketing copywriter. Given text describing features, audience, and USPs, compose compelling ~150 word marketing copy. Output just the copy as a single text block."
        },
        @{
          name = "marketing-editor"
          instructions = "You are an editor. Given draft copy, correct grammar, improve clarity, ensure consistent tone, format properly and make it polished. Output the final copy as a single text block."
        }
      )

      foreach ($agent in $agents) {
        $body = @{
          definition = @{
            kind = "prompt"
            model = $env:AGENT_MODEL
            instructions = $agent.instructions
          }
        } | ConvertTo-Json -Depth 5
        $uri = "$baseUrl/agents/$($agent.name)/versions?api-version=v1"
        Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
        Write-Host "Created agent: $($agent.name)"
      }

      # Create the workflow agent
      $workflowYaml = @"
kind: workflow
name: $($env:WORKFLOW_NAME)
trigger:
  kind: OnConversationStart
  id: trigger_wf
  actions:
    - kind: InvokeAzureAgent
      id: analyst
      agent:
        name: marketing-analyst
      description: Analyze product features, audience, and USPs
      conversationId: =System.ConversationId
      input:
        messages: =System.LastMessage
      output:
        messages: Local.LatestMessage
        autoSend: true
    - kind: InvokeAzureAgent
      id: copywriter
      agent:
        name: marketing-copywriter
      description: Write compelling marketing copy from analysis
      conversationId: =System.ConversationId
      input:
        messages: =Local.LatestMessage
      output:
        messages: Local.LatestMessage
        autoSend: true
    - kind: InvokeAzureAgent
      id: editor
      agent:
        name: marketing-editor
      description: Polish and finalize the marketing copy
      conversationId: =System.ConversationId
      input:
        messages: =Local.LatestMessage
      output:
        messages: Local.LatestMessage
        autoSend: true
id: ""
description: "Sequential marketing pipeline: Analyst -> Copywriter -> Editor"
"@

      $wfBody = @{
        definition = @{
          kind = "workflow"
          name = $env:WORKFLOW_NAME
          description = "Sequential marketing pipeline: Analyst -> Copywriter -> Editor"
          workflow = $workflowYaml
        }
      } | ConvertTo-Json -Depth 5
      $wfUri = "$baseUrl/agents/$($env:WORKFLOW_NAME)/versions?api-version=v1"
      $wfResult = Invoke-RestMethod -Uri $wfUri -Method Post -Headers $headers -Body $wfBody
      $wfVersion = $wfResult.version
      Write-Host "Created workflow: $($env:WORKFLOW_NAME):$wfVersion"

      # Publish as Agent Application
      $armToken = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token
      $armHeaders = @{
        "Authorization" = "Bearer $armToken"
        "Content-Type" = "application/json"
      }
      $armBase = "https://management.azure.com/subscriptions/$($env:SUBSCRIPTION_ID)/resourceGroups/$($env:RESOURCE_GROUP)/providers/Microsoft.CognitiveServices/accounts/$($env:ACCOUNT_NAME)/projects/$($env:PROJECT_NAME)"

      # Create application
      $appBody = @{
        properties = @{
          agents = @(@{ agentName = $env:WORKFLOW_NAME })
          displayName = "Marketing Pipeline Application"
          description = "Sequential workflow: Analyst -> Copywriter -> Editor"
        }
      } | ConvertTo-Json -Depth 5
      Invoke-RestMethod -Uri "$armBase/applications/$($env:APP_NAME)?api-version=2026-01-15-preview" -Method Put -Headers $armHeaders -Body $appBody
      Write-Host "Created application: $($env:APP_NAME)"

      # Create deployment
      $deployBody = @{
        properties = @{
          displayName = "Marketing Pipeline Deployment"
          deploymentType = "Managed"
          protocols = @(@{ protocol = "Responses"; version = "1.0" })
          agents = @(@{ agentName = $env:WORKFLOW_NAME; agentVersion = "$wfVersion" })
        }
      } | ConvertTo-Json -Depth 5
      Invoke-RestMethod -Uri "$armBase/applications/$($env:APP_NAME)/agentdeployments/$($env:DEPLOY_NAME)?api-version=2026-01-15-preview" -Method Put -Headers $armHeaders -Body $deployBody
      Write-Host "Created deployment: $($env:DEPLOY_NAME)"

      # Output results
      $DeploymentScriptOutputs = @{
        workflowName = $env:WORKFLOW_NAME
        workflowVersion = "$wfVersion"
        applicationName = $env:APP_NAME
        deploymentName = $env:DEPLOY_NAME
        endpoint = "$armBase/applications/$($env:APP_NAME)"
      }
    '''
  }
  dependsOn: [
    scriptRoleAssignment
    scriptContributorRole
  ]
}

output workflowName string = workflowName
output applicationName string = applicationName
output deploymentName string = deploymentName
