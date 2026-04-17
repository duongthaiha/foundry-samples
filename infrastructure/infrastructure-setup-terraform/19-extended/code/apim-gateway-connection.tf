# -----------------------------------------------------------------------------
# APIM gateway connection on the Foundry project
# Mirrors Bicep: modules-network-secured/apim-gateway-connection.bicep
# -----------------------------------------------------------------------------

locals {
  default_apim_model_deployments = [
    {
      name = var.model_name
      properties = {
        model = {
          name    = var.model_name
          version = var.model_version
          format  = var.model_format
        }
      }
    }
  ]
  resolved_apim_model_deployments = length(var.apim_model_deployments) > 0 ? var.apim_model_deployments : local.default_apim_model_deployments

  apim_id = local.apim_passed_in ? data.azurerm_api_management.existing[0].id : (
    var.deploy_api_management ? azurerm_api_management.apim[0].id : ""
  )
  apim_gateway_url = local.apim_passed_in ? data.azurerm_api_management.existing[0].gateway_url : (
    var.deploy_api_management ? azurerm_api_management.apim[0].gateway_url : ""
  )
  apim_identity_principal_id = local.apim_passed_in ? (
    try(data.azurerm_api_management.existing[0].identity[0].principal_id, null)
    ) : (
    var.deploy_api_management ? azurerm_api_management.apim[0].identity[0].principal_id : null
  )

  apim_openapi_spec_url = "https://raw.githubusercontent.com/Azure/azure-rest-api-specs/main/specification/cognitiveservices/data-plane/AzureOpenAI/inference/stable/${var.apim_inference_api_version}/inference.json"
  ai_services_endpoint  = "https://${local.account_name}.openai.azure.com"
  apim_api_path         = "openai"
}

# ---- Import Azure OpenAI API into APIM --------------------------------------
resource "azurerm_api_management_api" "openai" {
  count                 = local.apim_configured ? 1 : 0
  name                  = "azure-openai"
  resource_group_name   = local.apim_passed_in ? local.apim_parts[4] : azurerm_resource_group.rg.name
  api_management_name   = local.apim_name
  revision              = "1"
  display_name          = "Azure OpenAI Service API"
  path                  = local.apim_api_path
  protocols             = ["https"]
  service_url           = "${local.ai_services_endpoint}/openai"
  subscription_required = false

  import {
    content_format = "openapi-link"
    content_value  = local.apim_openapi_spec_url
  }
}

# ---- Managed-identity auth policy ------------------------------------------
resource "azurerm_api_management_api_policy" "openai" {
  count               = local.apim_configured ? 1 : 0
  api_name            = azurerm_api_management_api.openai[0].name
  api_management_name = local.apim_name
  resource_group_name = local.apim_passed_in ? local.apim_parts[4] : azurerm_resource_group.rg.name

  xml_content = "<policies><inbound><base /><authentication-managed-identity resource=\"https://cognitiveservices.azure.com/\" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>"
}

# ---- Grant APIM MI Cognitive Services OpenAI User on the Foundry account ----
resource "azurerm_role_assignment" "apim_openai_user" {
  count              = local.apim_configured && local.apim_identity_principal_id != null ? 1 : 0
  scope              = azapi_resource.ai_account.id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids.cognitive_services_openai_user}"
  principal_id       = local.apim_identity_principal_id
  principal_type     = "ServicePrincipal"
}

# ---- Fetch master subscription primary key from APIM ------------------------
data "azapi_resource_action" "apim_master_subscription_keys" {
  count                  = local.apim_configured ? 1 : 0
  type                   = "Microsoft.ApiManagement/service/subscriptions@2024-05-01"
  resource_id            = "${local.apim_id}/subscriptions/master"
  action                 = "listSecrets"
  method                 = "POST"
  response_export_values = ["primaryKey"]
}

# ---- Create the ApiManagement connection on the project ---------------------
resource "azapi_resource" "apim_gateway_connection" {
  count                     = local.apim_configured ? 1 : 0
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = var.apim_connection_name
  parent_id                 = azapi_resource.ai_project.id
  schema_validation_enabled = false

  body = {
    properties = {
      category      = "ApiManagement"
      target        = "${local.apim_gateway_url}/${local.apim_api_path}"
      authType      = "ApiKey"
      isSharedToAll = true
      credentials = {
        key = data.azapi_resource_action.apim_master_subscription_keys[0].output.primaryKey
      }
      metadata = {
        deploymentInPath    = "true"
        inferenceAPIVersion = var.apim_inference_api_version
        models              = jsonencode(local.resolved_apim_model_deployments)
      }
    }
  }

  depends_on = [
    azapi_resource.project_capability_host,
    azurerm_api_management_api_policy.openai,
  ]
}
