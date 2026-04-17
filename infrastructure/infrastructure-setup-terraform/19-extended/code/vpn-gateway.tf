# -----------------------------------------------------------------------------
# VPN Gateway (optional)
# Mirrors Bicep: modules-network-secured/vpn-gateway.bicep
# -----------------------------------------------------------------------------

resource "azurerm_subnet" "gateway" {
  count                = var.deploy_vpn_gateway ? 1 : 0
  name                 = "GatewaySubnet"
  resource_group_name  = local.existing_vnet_passed_in ? local.vnet_rg : azurerm_resource_group.rg.name
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.vpn_gateway_subnet_prefix != "" ? var.vpn_gateway_subnet_prefix : var.gateway_subnet_prefix]

  depends_on = [azurerm_virtual_network.vnet]
}

resource "azurerm_public_ip" "vpn" {
  count               = var.deploy_vpn_gateway ? 1 : 0
  name                = "${var.vpn_gateway_name}-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_virtual_network_gateway" "vpn" {
  count               = var.deploy_vpn_gateway ? 1 : 0
  name                = var.vpn_gateway_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  type                = "Vpn"
  vpn_type            = var.vpn_type
  sku                 = var.vpn_gateway_sku

  ip_configuration {
    name                          = "vnetGatewayConfig0"
    public_ip_address_id          = azurerm_public_ip.vpn[0].id
    subnet_id                     = azurerm_subnet.gateway[0].id
    private_ip_address_allocation = "Dynamic"
  }
}
