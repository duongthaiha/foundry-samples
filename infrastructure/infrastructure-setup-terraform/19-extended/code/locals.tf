# ---------------------------------------------------------------------
# Naming / suffix
# ---------------------------------------------------------------------
# Generate a 4-char lowercase unique suffix that is stable across applies.
resource "random_string" "unique_suffix" {
  length  = 4
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  unique_suffix = random_string.unique_suffix.result

  account_name                = lower("${var.ai_services}${local.unique_suffix}")
  project_name                = lower("${var.first_project_name}${local.unique_suffix}")
  cosmos_db_name              = lower("${var.ai_services}${local.unique_suffix}cosmosdb")
  ai_search_name              = lower("${var.ai_services}${local.unique_suffix}search")
  azure_storage_name          = lower("${var.ai_services}${local.unique_suffix}storage")
  api_management_service_name = lower("${var.ai_services}${local.unique_suffix}apim")
  app_insights_name           = lower("${var.ai_services}${local.unique_suffix}appinsights")
  cross_region_openai_name    = lower("${var.ai_services}${local.unique_suffix}openai-${var.cross_region_location}")

  # Existing resource flags
  storage_passed_in       = var.azure_storage_account_resource_id != ""
  search_passed_in        = var.ai_search_resource_id != ""
  cosmos_passed_in        = var.azure_cosmosdb_account_resource_id != ""
  existing_vnet_passed_in = var.existing_vnet_resource_id != ""
  apim_passed_in          = var.api_management_resource_id != ""
  fabric_passed_in        = var.fabric_workspace_resource_id != ""

  # Parse resource IDs: /subscriptions/{sub}/resourceGroups/{rg}/providers/{provider}/{type}/{name}
  # parts index: 0="" 1=subscriptions 2={sub} 3=resourceGroups 4={rg} ... last={name}
  storage_parts = local.storage_passed_in ? split("/", var.azure_storage_account_resource_id) : []
  search_parts  = local.search_passed_in ? split("/", var.ai_search_resource_id) : []
  cosmos_parts  = local.cosmos_passed_in ? split("/", var.azure_cosmosdb_account_resource_id) : []
  vnet_parts    = local.existing_vnet_passed_in ? split("/", var.existing_vnet_resource_id) : []
  apim_parts    = local.apim_passed_in ? split("/", var.api_management_resource_id) : []
  fabric_parts  = local.fabric_passed_in ? split("/", var.fabric_workspace_resource_id) : []

  storage_sub_id = local.storage_passed_in ? local.storage_parts[2] : data.azurerm_client_config.current.subscription_id
  storage_rg     = local.storage_passed_in ? local.storage_parts[4] : azurerm_resource_group.rg.name
  storage_name   = local.storage_passed_in ? element(local.storage_parts, length(local.storage_parts) - 1) : local.azure_storage_name

  search_sub_id = local.search_passed_in ? local.search_parts[2] : data.azurerm_client_config.current.subscription_id
  search_rg     = local.search_passed_in ? local.search_parts[4] : azurerm_resource_group.rg.name
  search_name   = local.search_passed_in ? element(local.search_parts, length(local.search_parts) - 1) : local.ai_search_name

  cosmos_sub_id = local.cosmos_passed_in ? local.cosmos_parts[2] : data.azurerm_client_config.current.subscription_id
  cosmos_rg     = local.cosmos_passed_in ? local.cosmos_parts[4] : azurerm_resource_group.rg.name
  cosmos_name   = local.cosmos_passed_in ? element(local.cosmos_parts, length(local.cosmos_parts) - 1) : local.cosmos_db_name

  vnet_sub_id = local.existing_vnet_passed_in ? local.vnet_parts[2] : data.azurerm_client_config.current.subscription_id
  vnet_rg     = local.existing_vnet_passed_in ? local.vnet_parts[4] : azurerm_resource_group.rg.name
  vnet_name   = local.existing_vnet_passed_in ? element(local.vnet_parts, length(local.vnet_parts) - 1) : var.vnet_name

  fabric_name = local.fabric_passed_in ? element(local.fabric_parts, length(local.fabric_parts) - 1) : ""

  # APIM resolved identifiers (either newly created or existing)
  apim_configured = var.deploy_api_management || local.apim_passed_in

  apim_name = (
    var.deploy_api_management ?
    (length(azurerm_api_management.apim) > 0 ? azurerm_api_management.apim[0].name : local.api_management_service_name) :
    (local.apim_passed_in ? element(local.apim_parts, length(local.apim_parts) - 1) : "")
  )

  # Address-space defaults mirror the Bicep template
  default_vnet_address_prefix   = "192.168.0.0/16"
  effective_vnet_address_prefix = var.vnet_address_prefix != "" ? var.vnet_address_prefix : local.default_vnet_address_prefix
  effective_agent_subnet_prefix = var.agent_subnet_prefix != "" ? var.agent_subnet_prefix : cidrsubnet(local.effective_vnet_address_prefix, 8, 0)
  effective_pe_subnet_prefix    = var.pe_subnet_prefix != "" ? var.pe_subnet_prefix : cidrsubnet(local.effective_vnet_address_prefix, 8, 1)
  effective_mcp_subnet_prefix   = var.mcp_subnet_prefix != "" ? var.mcp_subnet_prefix : cidrsubnet(local.effective_vnet_address_prefix, 8, 2)
  effective_apim_subnet_prefix  = var.apim_subnet_prefix != "" ? var.apim_subnet_prefix : cidrsubnet(local.effective_vnet_address_prefix, 8, 3)

  # Canary regions use westus for Cosmos
  canary_regions  = ["eastus2euap", "centraluseuap"]
  cosmos_location = contains(local.canary_regions, var.location) ? "westus" : var.location

  # Some regions don't support Standard_ZRS — use Standard_GRS
  no_zrs_regions      = ["southindia", "westus"]
  storage_replication = contains(local.no_zrs_regions, var.location) ? "GRS" : "ZRS"

  # ---- VNet + subnet IDs resolved downstream ----
  virtual_network_id = local.existing_vnet_passed_in ? data.azurerm_virtual_network.existing[0].id : azurerm_virtual_network.vnet[0].id
  agent_subnet_id    = local.existing_vnet_passed_in ? "${local.virtual_network_id}/subnets/${var.agent_subnet_name}" : azurerm_subnet.agent[0].id
  pe_subnet_id       = local.existing_vnet_passed_in ? "${local.virtual_network_id}/subnets/${var.pe_subnet_name}" : azurerm_subnet.pe[0].id
  mcp_subnet_id      = local.existing_vnet_passed_in ? "${local.virtual_network_id}/subnets/${var.mcp_subnet_name}" : azurerm_subnet.mcp[0].id

  # Workspace id → GUID (formatted 8-4-4-4-12)
  project_workspace_id = azapi_resource.ai_project.output.properties.internalId
  project_workspace_guid = format(
    "%s-%s-%s-%s-%s",
    substr(local.project_workspace_id, 0, 8),
    substr(local.project_workspace_id, 8, 4),
    substr(local.project_workspace_id, 12, 4),
    substr(local.project_workspace_id, 16, 4),
    substr(local.project_workspace_id, 20, 12),
  )
}

data "azurerm_client_config" "current" {}
