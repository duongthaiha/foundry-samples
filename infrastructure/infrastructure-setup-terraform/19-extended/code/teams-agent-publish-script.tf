# -----------------------------------------------------------------------------
# Teams Agent Publish Script (optional)
# Mirrors Bicep: modules-network-secured/teams-agent-publish-script.bicep
#
# Creates an Agent Application + Managed Deployment, then emits the Activity
# Protocol URL + Bot client ID for wiring into the Bot Service / App Gateway.
# -----------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "teams_publish" {
  count               = var.deploy_teams_publishing ? 1 : 0
  name                = "${var.teams_application_name}-publish-identity"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_role_assignment" "teams_publish_contrib" {
  count              = var.deploy_teams_publishing ? 1 : 0
  scope              = azurerm_resource_group.rg.id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
  principal_id       = azurerm_user_assigned_identity.teams_publish[0].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "teams_publish_ai" {
  count              = var.deploy_teams_publishing ? 1 : 0
  scope              = azapi_resource.ai_account.id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/64702f94-c441-49e6-a78b-ef80e0188fee"
  principal_id       = azurerm_user_assigned_identity.teams_publish[0].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azapi_resource" "teams_publish_script" {
  count                     = var.deploy_teams_publishing ? 1 : 0
  type                      = "Microsoft.Resources/deploymentScripts@2023-08-01"
  name                      = "${var.teams_application_name}-publish-script"
  parent_id                 = azurerm_resource_group.rg.id
  location                  = var.location
  schema_validation_enabled = false

  response_export_values = ["properties.outputs"]

  body = {
    kind = "AzurePowerShell"
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        (azurerm_user_assigned_identity.teams_publish[0].id) = {}
      }
    }
    properties = {
      azPowerShellVersion = "12.0"
      retentionInterval   = "PT1H"
      timeout             = "PT10M"
      environmentVariables = [
        { name = "ACCOUNT_NAME", value = local.account_name },
        { name = "PROJECT_NAME", value = local.project_name },
        { name = "AGENT_NAME", value = var.teams_agent_name },
        { name = "AGENT_VERSION", value = var.teams_agent_version },
        { name = "APP_NAME", value = var.teams_application_name },
        { name = "DEPLOY_NAME", value = var.teams_deployment_name },
        { name = "SUBSCRIPTION_ID", value = data.azurerm_client_config.current.subscription_id },
        { name = "RESOURCE_GROUP", value = azurerm_resource_group.rg.name },
      ]
      scriptContent = <<-EOT
        $ErrorActionPreference = 'Stop'

        $armBase = "https://management.azure.com/subscriptions/$($env:SUBSCRIPTION_ID)/resourceGroups/$($env:RESOURCE_GROUP)/providers/Microsoft.CognitiveServices/accounts/$($env:ACCOUNT_NAME)/projects/$($env:PROJECT_NAME)"

        $armToken = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token
        $armHeaders = @{
          "Authorization" = "Bearer $armToken"
          "Content-Type" = "application/json"
        }

        $agentVersion = $env:AGENT_VERSION
        if ([string]::IsNullOrEmpty($agentVersion)) {
          $aiToken = (Get-AzAccessToken -ResourceUrl "https://ai.azure.com").Token
          $aiHeaders = @{ "Authorization" = "Bearer $aiToken"; "Content-Type" = "application/json" }
          $baseUrl = "https://$($env:ACCOUNT_NAME).services.ai.azure.com/api/projects/$($env:PROJECT_NAME)"
          $versions = Invoke-RestMethod -Uri "$baseUrl/agents/$($env:AGENT_NAME)/versions?api-version=v1" -Headers $aiHeaders
          $agentVersion = $versions.data[0].version
          Write-Host "Resolved latest agent version: $agentVersion"
        }

        $appBody = @{
          properties = @{
            agents = @(@{ agentName = $env:AGENT_NAME })
            displayName = "$($env:APP_NAME)"
            description = "Published agent for Teams integration"
          }
        } | ConvertTo-Json -Depth 5
        try {
          Invoke-RestMethod -Uri "$armBase/applications/$($env:APP_NAME)?api-version=2026-01-15-preview" -Method Put -Headers $armHeaders -Body $appBody
          Write-Host "Created application: $($env:APP_NAME)"
        } catch {
          Write-Host "Application may already exist, continuing..."
        }

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
          Invoke-RestMethod -Uri "$armBase/applications/$($env:APP_NAME)/agentdeployments/$($env:DEPLOY_NAME)?api-version=2026-01-15-preview" -Method Put -Headers $armHeaders -Body $deployBody
          Write-Host "Created deployment: $($env:DEPLOY_NAME)"
        } catch {
          Write-Host "Deployment may already exist, continuing..."
        }

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
      EOT
    }
  }

  depends_on = [
    azurerm_role_assignment.teams_publish_contrib,
    azurerm_role_assignment.teams_publish_ai,
    azapi_resource.project_capability_host,
  ]
}

locals {
  teams_publish_outputs                 = var.deploy_teams_publishing ? try(azapi_resource.teams_publish_script[0].output.properties.outputs, {}) : {}
  teams_activity_protocol_url_effective = var.teams_activity_protocol_url != "" ? var.teams_activity_protocol_url : try(local.teams_publish_outputs.activityProtocolUrl, "")
  teams_bot_client_id_effective         = var.teams_bot_client_id != "" ? var.teams_bot_client_id : try(local.teams_publish_outputs.botClientId, "")
}
