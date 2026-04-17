# -----------------------------------------------------------------------------
# Application Insights (optional)
# Mirrors Bicep: modules-network-secured/application-insights.bicep
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "law" {
  count               = var.deploy_application_insights ? 1 : 0
  name                = "${local.app_insights_name}-law"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "app" {
  count               = var.deploy_application_insights ? 1 : 0
  name                = local.app_insights_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.law[0].id
}

# Connect App Insights to the Foundry account.
resource "azapi_resource" "app_insights_connection" {
  count                     = var.deploy_application_insights ? 1 : 0
  type                      = "Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview"
  name                      = local.app_insights_name
  parent_id                 = azapi_resource.ai_account.id
  schema_validation_enabled = false

  body = {
    properties = {
      category      = "AppInsights"
      target        = azurerm_application_insights.app[0].id
      authType      = "ApiKey"
      isSharedToAll = true
      credentials = {
        key = azurerm_application_insights.app[0].connection_string
      }
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_application_insights.app[0].id
      }
    }
  }
}
