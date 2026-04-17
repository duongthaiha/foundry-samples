# -----------------------------------------------------------------------------
# Cross-region OpenAI (optional) + APIM API + Private Endpoint + DNS
# Mirrors Bicep: modules-network-secured/cross-region-openai-connection.bicep
#
# Requires: APIM to be configured (apim_configured).
# Azure enforces disableLocalAuth on new OpenAI resources so we front with
# APIM + managed-identity auth and expose a project ApiManagement connection.
# -----------------------------------------------------------------------------

locals {
  cross_region_enabled   = var.deploy_cross_region_openai && local.apim_configured
  cross_region_api_name  = "azure-openai-${var.cross_region_location}"
  cross_region_api_path  = "openai-${var.cross_region_location}"
  cross_region_conn_name = "apim-gateway-${var.cross_region_location}"

  cross_region_static_models = [
    {
      name = var.cross_region_model_name
      properties = {
        model = {
          name    = var.cross_region_model_name
          version = var.cross_region_model_version
          format  = "OpenAI"
        }
      }
    }
  ]
}

# ---- Cross-region Azure OpenAI account --------------------------------------
resource "azapi_resource" "cross_region_openai" {
  count                     = local.cross_region_enabled ? 1 : 0
  type                      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name                      = local.cross_region_openai_name
  parent_id                 = azurerm_resource_group.rg.id
  location                  = var.cross_region_location
  schema_validation_enabled = false

  body = {
    kind = "OpenAI"
    sku  = { name = "S0" }
    properties = {
      publicNetworkAccess = "Enabled"
      customSubDomainName = local.cross_region_openai_name
    }
  }
}

# ---- Cross-region model deployment ------------------------------------------
resource "azapi_resource" "cross_region_model_deployment" {
  count                     = local.cross_region_enabled ? 1 : 0
  type                      = "Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview"
  name                      = var.cross_region_model_name
  parent_id                 = azapi_resource.cross_region_openai[0].id
  schema_validation_enabled = false

  body = {
    sku = {
      name     = var.cross_region_model_sku
      capacity = var.cross_region_model_capacity
    }
    properties = {
      model = {
        name    = var.cross_region_model_name
        format  = "OpenAI"
        version = var.cross_region_model_version
      }
    }
  }
}

# ---- Grant APIM MI Cognitive Services OpenAI User on cross-region OpenAI ----
resource "azurerm_role_assignment" "apim_cross_region_openai_user" {
  count              = local.cross_region_enabled && local.apim_identity_principal_id != null ? 1 : 0
  scope              = azapi_resource.cross_region_openai[0].id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids.cognitive_services_openai_user}"
  principal_id       = local.apim_identity_principal_id
  principal_type     = "ServicePrincipal"
}

# ---- APIM API for cross-region backend --------------------------------------
resource "azurerm_api_management_api" "cross_region" {
  count                 = local.cross_region_enabled ? 1 : 0
  name                  = local.cross_region_api_name
  resource_group_name   = local.apim_passed_in ? local.apim_parts[4] : azurerm_resource_group.rg.name
  api_management_name   = local.apim_name
  revision              = "1"
  display_name          = "Azure OpenAI ${var.cross_region_location}"
  path                  = local.cross_region_api_path
  protocols             = ["https"]
  service_url           = "https://${local.cross_region_openai_name}.openai.azure.com/openai"
  subscription_required = false

  import {
    content_format = "openapi-link"
    content_value  = local.apim_openapi_spec_url
  }
}

resource "azurerm_api_management_api_policy" "cross_region" {
  count               = local.cross_region_enabled ? 1 : 0
  api_name            = azurerm_api_management_api.cross_region[0].name
  api_management_name = local.apim_name
  resource_group_name = local.apim_passed_in ? local.apim_parts[4] : azurerm_resource_group.rg.name

  xml_content = "<policies><inbound><base /><authentication-managed-identity resource=\"https://cognitiveservices.azure.com/\" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>"
}

# ---- Private Endpoint in primary VNet ---------------------------------------
resource "azurerm_private_endpoint" "cross_region_openai" {
  count               = local.cross_region_enabled ? 1 : 0
  name                = "${local.cross_region_openai_name}-private-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = local.pe_subnet_id

  private_service_connection {
    name                           = "${local.cross_region_openai_name}-private-link-service-connection"
    private_connection_resource_id = azapi_resource.cross_region_openai[0].id
    is_manual_connection           = false
    subresource_names              = ["account"]
  }

  private_dns_zone_group {
    name                 = "${local.cross_region_openai_name}-dns-group"
    private_dns_zone_ids = [local.dns_zone_ids.openai]
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.openai]
}

# ---- APIM Gateway connection on project for cross-region --------------------
resource "azapi_resource" "cross_region_connection" {
  count                     = local.cross_region_enabled ? 1 : 0
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = local.cross_region_conn_name
  parent_id                 = azapi_resource.ai_project.id
  schema_validation_enabled = false

  body = {
    properties = {
      category      = "ApiManagement"
      target        = "${local.apim_gateway_url}/${local.cross_region_api_path}"
      authType      = "ApiKey"
      isSharedToAll = true
      credentials = {
        key = data.azapi_resource_action.apim_master_subscription_keys[0].output.primaryKey
      }
      metadata = {
        deploymentInPath    = "true"
        inferenceAPIVersion = var.apim_inference_api_version
        models              = jsonencode(local.cross_region_static_models)
      }
    }
  }

  depends_on = [
    azapi_resource.cross_region_model_deployment,
    azurerm_api_management_api_policy.cross_region,
    azurerm_role_assignment.apim_cross_region_openai_user,
    azapi_resource.project_capability_host,
  ]
}
