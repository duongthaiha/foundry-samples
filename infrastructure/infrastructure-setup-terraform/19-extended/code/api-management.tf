# -----------------------------------------------------------------------------
# API Management service (optional)
# Mirrors Bicep: modules-network-secured/api-management.bicep
# -----------------------------------------------------------------------------

resource "azurerm_api_management" "apim" {
  count               = var.deploy_api_management ? 1 : 0
  name                = local.api_management_service_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  publisher_email     = var.publisher_email
  publisher_name      = var.publisher_name
  sku_name            = "${var.api_management_sku}_${var.api_management_capacity}"

  identity {
    type = "SystemAssigned"
  }

  # Outbound VNet integration for private backend connectivity (External type).
  virtual_network_type = "External"
  virtual_network_configuration {
    subnet_id = local.apim_subnet_id
  }

  # publicNetworkAccess is implicitly Enabled during creation; private endpoint
  # should be configured separately to restrict access.

  depends_on = [
    azurerm_subnet_network_security_group_association.apim
  ]
}

# ---- Reference to existing APIM (when resource ID passed in) ----------------
data "azurerm_api_management" "existing" {
  count               = local.apim_passed_in ? 1 : 0
  name                = element(local.apim_parts, length(local.apim_parts) - 1)
  resource_group_name = local.apim_parts[4]
}
