# -----------------------------------------------------------------------------
# Workflow Deployment Script (optional)
# Mirrors Bicep: modules-network-secured/workflow-deployment.bicep
#
# Creates three prompt agents + a sequential workflow agent + an Agent
# Application + Managed Deployment. Uses a deploymentScript because all of
# these are Foundry data-plane operations (not ARM resources).
# -----------------------------------------------------------------------------

# Managed Identity for the deployment script
resource "azurerm_user_assigned_identity" "workflow_script" {
  count               = var.deploy_workflow ? 1 : 0
  name                = "${var.workflow_name}-script-identity"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Azure AI Developer on the account
resource "azurerm_role_assignment" "workflow_script_ai" {
  count              = var.deploy_workflow ? 1 : 0
  scope              = azapi_resource.ai_account.id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/64702f94-c441-49e6-a78b-ef80e0188fee"
  principal_id       = azurerm_user_assigned_identity.workflow_script[0].principal_id
  principal_type     = "ServicePrincipal"
}

# Contributor on the resource group (for application PUT)
resource "azurerm_role_assignment" "workflow_script_contrib" {
  count              = var.deploy_workflow ? 1 : 0
  scope              = azurerm_resource_group.rg.id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
  principal_id       = azurerm_user_assigned_identity.workflow_script[0].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azapi_resource" "workflow_script" {
  count                     = var.deploy_workflow ? 1 : 0
  type                      = "Microsoft.Resources/deploymentScripts@2023-08-01"
  name                      = "${var.workflow_name}-deploy-script"
  parent_id                 = azurerm_resource_group.rg.id
  location                  = var.location
  schema_validation_enabled = false

  body = {
    kind = "AzurePowerShell"
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        (azurerm_user_assigned_identity.workflow_script[0].id) = {}
      }
    }
    properties = {
      azPowerShellVersion = "12.0"
      retentionInterval   = "PT1H"
      timeout             = "PT10M"
      environmentVariables = [
        { name = "ACCOUNT_NAME", value = local.account_name },
        { name = "PROJECT_NAME", value = local.project_name },
        { name = "AGENT_MODEL", value = var.workflow_agent_model },
        { name = "WORKFLOW_NAME", value = var.workflow_name },
        { name = "APP_NAME", value = var.workflow_application_name },
        { name = "DEPLOY_NAME", value = var.workflow_deployment_name },
        { name = "SUBSCRIPTION_ID", value = data.azurerm_client_config.current.subscription_id },
        { name = "RESOURCE_GROUP", value = azurerm_resource_group.rg.name },
      ]
      scriptContent = <<-EOT
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

        $appBody = @{
          properties = @{
            agents = @(@{ agentName = $env:WORKFLOW_NAME })
            displayName = "Marketing Pipeline Application"
            description = "Sequential workflow: Analyst -> Copywriter -> Editor"
          }
        } | ConvertTo-Json -Depth 5
        Invoke-RestMethod -Uri "$armBase/applications/$($env:APP_NAME)?api-version=2026-01-15-preview" -Method Put -Headers $armHeaders -Body $appBody
        Write-Host "Created application: $($env:APP_NAME)"

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

        $DeploymentScriptOutputs = @{
          workflowName = $env:WORKFLOW_NAME
          workflowVersion = "$wfVersion"
          applicationName = $env:APP_NAME
          deploymentName = $env:DEPLOY_NAME
          endpoint = "$armBase/applications/$($env:APP_NAME)"
        }
      EOT
    }
  }

  depends_on = [
    azurerm_role_assignment.workflow_script_ai,
    azurerm_role_assignment.workflow_script_contrib,
    azapi_resource.project_capability_host,
  ]
}
