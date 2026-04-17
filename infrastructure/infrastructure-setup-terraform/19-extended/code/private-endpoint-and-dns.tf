# -----------------------------------------------------------------------------
# Private Endpoints + Private DNS Zones + Zone Groups + VNet Links
# Mirrors Bicep: modules-network-secured/private-endpoint-and-dns.bicep
#
# Creates PEs for: AI Foundry account, AI Search, Storage (blob), Cosmos (Sql),
#                  Microsoft Fabric (optional), API Management (optional).
# Creates/Links private DNS zones unless the zone FQDN is mapped to an
# existing resource group in `var.existing_dns_zones`.
# -----------------------------------------------------------------------------

locals {
  dns_zone_names = {
    ai_services        = "privatelink.services.ai.azure.com"
    openai             = "privatelink.openai.azure.com"
    cognitive_services = "privatelink.cognitiveservices.azure.com"
    search             = "privatelink.search.windows.net"
    storage_blob       = "privatelink.blob.core.windows.net"
    cosmos             = "privatelink.documents.azure.com"
    fabric             = "privatelink.fabric.microsoft.com"
    api_management     = "privatelink.azure-api.net"
  }

  dns_zone_rg = {
    ai_services        = lookup(var.existing_dns_zones, local.dns_zone_names.ai_services, "")
    openai             = lookup(var.existing_dns_zones, local.dns_zone_names.openai, "")
    cognitive_services = lookup(var.existing_dns_zones, local.dns_zone_names.cognitive_services, "")
    search             = lookup(var.existing_dns_zones, local.dns_zone_names.search, "")
    storage_blob       = lookup(var.existing_dns_zones, local.dns_zone_names.storage_blob, "")
    cosmos             = lookup(var.existing_dns_zones, local.dns_zone_names.cosmos, "")
    fabric             = lookup(var.existing_dns_zones, local.dns_zone_names.fabric, "")
    api_management     = lookup(var.existing_dns_zones, local.dns_zone_names.api_management, "")
  }
}

# =============================================================================
# PRIVATE DNS ZONES (create or reference existing)
# =============================================================================
resource "azurerm_private_dns_zone" "ai_services" {
  count               = local.dns_zone_rg.ai_services == "" ? 1 : 0
  name                = local.dns_zone_names.ai_services
  resource_group_name = azurerm_resource_group.rg.name
}
data "azurerm_private_dns_zone" "ai_services" {
  count               = local.dns_zone_rg.ai_services == "" ? 0 : 1
  name                = local.dns_zone_names.ai_services
  resource_group_name = local.dns_zone_rg.ai_services
}

resource "azurerm_private_dns_zone" "openai" {
  count               = local.dns_zone_rg.openai == "" ? 1 : 0
  name                = local.dns_zone_names.openai
  resource_group_name = azurerm_resource_group.rg.name
}
data "azurerm_private_dns_zone" "openai" {
  count               = local.dns_zone_rg.openai == "" ? 0 : 1
  name                = local.dns_zone_names.openai
  resource_group_name = local.dns_zone_rg.openai
}

resource "azurerm_private_dns_zone" "cognitive_services" {
  count               = local.dns_zone_rg.cognitive_services == "" ? 1 : 0
  name                = local.dns_zone_names.cognitive_services
  resource_group_name = azurerm_resource_group.rg.name
}
data "azurerm_private_dns_zone" "cognitive_services" {
  count               = local.dns_zone_rg.cognitive_services == "" ? 0 : 1
  name                = local.dns_zone_names.cognitive_services
  resource_group_name = local.dns_zone_rg.cognitive_services
}

resource "azurerm_private_dns_zone" "search" {
  count               = local.dns_zone_rg.search == "" ? 1 : 0
  name                = local.dns_zone_names.search
  resource_group_name = azurerm_resource_group.rg.name
}
data "azurerm_private_dns_zone" "search" {
  count               = local.dns_zone_rg.search == "" ? 0 : 1
  name                = local.dns_zone_names.search
  resource_group_name = local.dns_zone_rg.search
}

resource "azurerm_private_dns_zone" "storage_blob" {
  count               = local.dns_zone_rg.storage_blob == "" ? 1 : 0
  name                = local.dns_zone_names.storage_blob
  resource_group_name = azurerm_resource_group.rg.name
}
data "azurerm_private_dns_zone" "storage_blob" {
  count               = local.dns_zone_rg.storage_blob == "" ? 0 : 1
  name                = local.dns_zone_names.storage_blob
  resource_group_name = local.dns_zone_rg.storage_blob
}

resource "azurerm_private_dns_zone" "cosmos" {
  count               = local.dns_zone_rg.cosmos == "" ? 1 : 0
  name                = local.dns_zone_names.cosmos
  resource_group_name = azurerm_resource_group.rg.name
}
data "azurerm_private_dns_zone" "cosmos" {
  count               = local.dns_zone_rg.cosmos == "" ? 0 : 1
  name                = local.dns_zone_names.cosmos
  resource_group_name = local.dns_zone_rg.cosmos
}

resource "azurerm_private_dns_zone" "fabric" {
  count               = local.fabric_passed_in && local.dns_zone_rg.fabric == "" ? 1 : 0
  name                = local.dns_zone_names.fabric
  resource_group_name = azurerm_resource_group.rg.name
}
data "azurerm_private_dns_zone" "fabric" {
  count               = local.fabric_passed_in && local.dns_zone_rg.fabric != "" ? 1 : 0
  name                = local.dns_zone_names.fabric
  resource_group_name = local.dns_zone_rg.fabric
}

resource "azurerm_private_dns_zone" "api_management" {
  count               = local.apim_configured && local.dns_zone_rg.api_management == "" ? 1 : 0
  name                = local.dns_zone_names.api_management
  resource_group_name = azurerm_resource_group.rg.name
}
data "azurerm_private_dns_zone" "api_management" {
  count               = local.apim_configured && local.dns_zone_rg.api_management != "" ? 1 : 0
  name                = local.dns_zone_names.api_management
  resource_group_name = local.dns_zone_rg.api_management
}

locals {
  dns_zone_ids = {
    ai_services        = local.dns_zone_rg.ai_services == "" ? azurerm_private_dns_zone.ai_services[0].id : data.azurerm_private_dns_zone.ai_services[0].id
    openai             = local.dns_zone_rg.openai == "" ? azurerm_private_dns_zone.openai[0].id : data.azurerm_private_dns_zone.openai[0].id
    cognitive_services = local.dns_zone_rg.cognitive_services == "" ? azurerm_private_dns_zone.cognitive_services[0].id : data.azurerm_private_dns_zone.cognitive_services[0].id
    search             = local.dns_zone_rg.search == "" ? azurerm_private_dns_zone.search[0].id : data.azurerm_private_dns_zone.search[0].id
    storage_blob       = local.dns_zone_rg.storage_blob == "" ? azurerm_private_dns_zone.storage_blob[0].id : data.azurerm_private_dns_zone.storage_blob[0].id
    cosmos             = local.dns_zone_rg.cosmos == "" ? azurerm_private_dns_zone.cosmos[0].id : data.azurerm_private_dns_zone.cosmos[0].id
    fabric             = local.fabric_passed_in ? (local.dns_zone_rg.fabric == "" ? azurerm_private_dns_zone.fabric[0].id : data.azurerm_private_dns_zone.fabric[0].id) : ""
    api_management     = local.apim_configured ? (local.dns_zone_rg.api_management == "" ? azurerm_private_dns_zone.api_management[0].id : data.azurerm_private_dns_zone.api_management[0].id) : ""
  }
}

# =============================================================================
# VNET LINKS (only for zones we created)
# =============================================================================
resource "azurerm_private_dns_zone_virtual_network_link" "ai_services" {
  count                 = local.dns_zone_rg.ai_services == "" ? 1 : 0
  name                  = "aiServices-${local.unique_suffix}-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.ai_services[0].name
  virtual_network_id    = local.virtual_network_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "openai" {
  count                 = local.dns_zone_rg.openai == "" ? 1 : 0
  name                  = "aiServicesOpenAI-${local.unique_suffix}-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.openai[0].name
  virtual_network_id    = local.virtual_network_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "cognitive_services" {
  count                 = local.dns_zone_rg.cognitive_services == "" ? 1 : 0
  name                  = "aiServicesCognitiveServices-${local.unique_suffix}-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.cognitive_services[0].name
  virtual_network_id    = local.virtual_network_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "search" {
  count                 = local.dns_zone_rg.search == "" ? 1 : 0
  name                  = "aiSearch-${local.unique_suffix}-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.search[0].name
  virtual_network_id    = local.virtual_network_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob" {
  count                 = local.dns_zone_rg.storage_blob == "" ? 1 : 0
  name                  = "storage-${local.unique_suffix}-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob[0].name
  virtual_network_id    = local.virtual_network_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "cosmos" {
  count                 = local.dns_zone_rg.cosmos == "" ? 1 : 0
  name                  = "cosmosDB-${local.unique_suffix}-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.cosmos[0].name
  virtual_network_id    = local.virtual_network_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "fabric" {
  count                 = local.fabric_passed_in && local.dns_zone_rg.fabric == "" ? 1 : 0
  name                  = "fabric-${local.unique_suffix}-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.fabric[0].name
  virtual_network_id    = local.virtual_network_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "api_management" {
  count                 = local.apim_configured && local.dns_zone_rg.api_management == "" ? 1 : 0
  name                  = "apiManagement-${local.unique_suffix}-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.api_management[0].name
  virtual_network_id    = local.virtual_network_id
}

# =============================================================================
# PRIVATE ENDPOINTS
# =============================================================================

# ---- AI Foundry account PE (3 zones) ----------------------------------------
resource "azurerm_private_endpoint" "ai_account" {
  name                = "${local.account_name}-private-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = local.pe_subnet_id

  private_service_connection {
    name                           = "${local.account_name}-private-link-service-connection"
    private_connection_resource_id = azapi_resource.ai_account.id
    is_manual_connection           = false
    subresource_names              = ["account"]
  }

  private_dns_zone_group {
    name = "${local.account_name}-dns-group"
    private_dns_zone_ids = [
      local.dns_zone_ids.ai_services,
      local.dns_zone_ids.openai,
      local.dns_zone_ids.cognitive_services,
    ]
  }

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.ai_services,
    azurerm_private_dns_zone_virtual_network_link.openai,
    azurerm_private_dns_zone_virtual_network_link.cognitive_services,
  ]
}

# ---- AI Search PE -----------------------------------------------------------
resource "azurerm_private_endpoint" "search" {
  name                = "${local.search_name}-private-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = local.pe_subnet_id

  private_service_connection {
    name                           = "${local.search_name}-private-link-service-connection"
    private_connection_resource_id = local.effective_search_id
    is_manual_connection           = false
    subresource_names              = ["searchService"]
  }

  private_dns_zone_group {
    name                 = "${local.search_name}-dns-group"
    private_dns_zone_ids = [local.dns_zone_ids.search]
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.search]
}

# ---- Storage (blob) PE ------------------------------------------------------
resource "azurerm_private_endpoint" "storage" {
  name                = "${local.storage_name}-private-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = local.pe_subnet_id

  private_service_connection {
    name                           = "${local.storage_name}-private-link-service-connection"
    private_connection_resource_id = local.effective_storage_id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "${local.storage_name}-dns-group"
    private_dns_zone_ids = [local.dns_zone_ids.storage_blob]
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.storage_blob]
}

# ---- Cosmos DB PE -----------------------------------------------------------
resource "azurerm_private_endpoint" "cosmos" {
  name                = "${local.cosmos_name}-private-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = local.pe_subnet_id

  private_service_connection {
    name                           = "${local.cosmos_name}-private-link-service-connection"
    private_connection_resource_id = local.effective_cosmos_id
    is_manual_connection           = false
    subresource_names              = ["Sql"]
  }

  private_dns_zone_group {
    name                 = "${local.cosmos_name}-dns-group"
    private_dns_zone_ids = [local.dns_zone_ids.cosmos]
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.cosmos]
}

# ---- Fabric PE (optional) ---------------------------------------------------
resource "azurerm_private_endpoint" "fabric" {
  count               = local.fabric_passed_in ? 1 : 0
  name                = "${local.fabric_name}-fabric-private-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = local.pe_subnet_id

  private_service_connection {
    name                           = "${local.fabric_name}-private-link-service-connection"
    private_connection_resource_id = var.fabric_workspace_resource_id
    is_manual_connection           = false
    subresource_names              = ["Fabric"]
  }

  private_dns_zone_group {
    name                 = "${local.fabric_name}-dns-group"
    private_dns_zone_ids = [local.dns_zone_ids.fabric]
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.fabric]
}

# ---- APIM PE (optional) -----------------------------------------------------
# Uses local.apim_name which resolves to the newly-created or existing APIM.
resource "azurerm_private_endpoint" "api_management" {
  count               = local.apim_configured ? 1 : 0
  name                = "${local.apim_name}-private-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = local.pe_subnet_id

  private_service_connection {
    name                           = "${local.apim_name}-private-link-service-connection"
    private_connection_resource_id = var.deploy_api_management ? azurerm_api_management.apim[0].id : var.api_management_resource_id
    is_manual_connection           = false
    subresource_names              = ["Gateway"]
  }

  private_dns_zone_group {
    name                 = "${local.apim_name}-dns-group"
    private_dns_zone_ids = [local.dns_zone_ids.api_management]
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.api_management]
}
