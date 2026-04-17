# -----------------------------------------------------------------------------
# Dependent resources: AI Search, Storage, Cosmos DB (create or reference)
# Mirrors Bicep:
#   - standard-dependent-resources.bicep
#   - validate-existing-resources.bicep
# -----------------------------------------------------------------------------

# ---- Existing-resource data sources (when IDs provided) ---------------------
data "azurerm_search_service" "existing" {
  count               = local.search_passed_in ? 1 : 0
  name                = local.search_name
  resource_group_name = local.search_rg
}

data "azurerm_storage_account" "existing" {
  count               = local.storage_passed_in ? 1 : 0
  name                = local.storage_name
  resource_group_name = local.storage_rg
}

data "azurerm_cosmosdb_account" "existing" {
  count               = local.cosmos_passed_in ? 1 : 0
  name                = local.cosmos_name
  resource_group_name = local.cosmos_rg
}

# ---- New AI Search (when no ID provided) ------------------------------------
resource "azurerm_search_service" "search" {
  count               = local.search_passed_in ? 0 : 1
  name                = local.ai_search_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  sku                 = "standard"

  local_authentication_enabled  = true
  authentication_failure_mode   = "http401WithBearerChallenge"
  public_network_access_enabled = false
  partition_count               = 1
  replica_count                 = 1
  semantic_search_sku           = null
  hosting_mode                  = "default"

  identity {
    type = "SystemAssigned"
  }

  network_rule_bypass_option = "AzureServices"
}

# ---- New Storage (when no ID provided) --------------------------------------
resource "azurerm_storage_account" "storage" {
  count                    = local.storage_passed_in ? 0 : 1
  name                     = local.azure_storage_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = var.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.storage_replication

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  public_network_access_enabled   = false

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

# ---- New Cosmos DB (when no ID provided) ------------------------------------
resource "azurerm_cosmosdb_account" "cosmos" {
  count                            = local.cosmos_passed_in ? 0 : 1
  name                             = local.cosmos_db_name
  resource_group_name              = azurerm_resource_group.rg.name
  location                         = local.cosmos_location
  kind                             = "GlobalDocumentDB"
  offer_type                       = "Standard"
  public_network_access_enabled    = false
  local_authentication_disabled    = true
  automatic_failover_enabled       = false
  multiple_write_locations_enabled = false
  free_tier_enabled                = false

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = local.cosmos_location
    failover_priority = 0
    zone_redundant    = false
  }
}

# ---- Aggregated "effective" identifiers downstream modules use --------------
locals {
  effective_search_id = local.search_passed_in ? data.azurerm_search_service.existing[0].id : azurerm_search_service.search[0].id
  effective_search_principal_id = local.search_passed_in ? (
    try(data.azurerm_search_service.existing[0].identity[0].principal_id, null)
  ) : azurerm_search_service.search[0].identity[0].principal_id

  effective_storage_id   = local.storage_passed_in ? data.azurerm_storage_account.existing[0].id : azurerm_storage_account.storage[0].id
  effective_storage_blob = local.storage_passed_in ? data.azurerm_storage_account.existing[0].primary_blob_endpoint : azurerm_storage_account.storage[0].primary_blob_endpoint

  effective_cosmos_id       = local.cosmos_passed_in ? data.azurerm_cosmosdb_account.existing[0].id : azurerm_cosmosdb_account.cosmos[0].id
  effective_cosmos_endpoint = local.cosmos_passed_in ? data.azurerm_cosmosdb_account.existing[0].endpoint : azurerm_cosmosdb_account.cosmos[0].endpoint
}
