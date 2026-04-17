# -----------------------------------------------------------------------------
# Virtual Network + subnets (agent, private endpoint, MCP, optional APIM)
#
# Mirrors Bicep modules:
#   - network-agent-vnet.bicep
#   - vnet.bicep
#   - existing-vnet.bicep
#   - subnet.bicep   (the APIM subnet is defined inline here)
# -----------------------------------------------------------------------------

# -- Existing VNet lookup (when useExistingVnet) ------------------------------
data "azurerm_virtual_network" "existing" {
  count               = local.existing_vnet_passed_in ? 1 : 0
  name                = local.vnet_name
  resource_group_name = local.vnet_rg
}

# -- New VNet + subnets -------------------------------------------------------
resource "azurerm_virtual_network" "vnet" {
  count               = local.existing_vnet_passed_in ? 0 : 1
  name                = local.vnet_name
  address_space       = [local.effective_vnet_address_prefix]
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "agent" {
  count                = local.existing_vnet_passed_in ? 0 : 1
  name                 = var.agent_subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = [local.effective_agent_subnet_prefix]

  delegation {
    name = "Microsoft.app/environments"
    service_delegation {
      name = "Microsoft.App/environments"
    }
  }
}

resource "azurerm_subnet" "pe" {
  count                = local.existing_vnet_passed_in ? 0 : 1
  name                 = var.pe_subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = [local.effective_pe_subnet_prefix]
}

resource "azurerm_subnet" "mcp" {
  count                = local.existing_vnet_passed_in ? 0 : 1
  name                 = var.mcp_subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = [local.effective_mcp_subnet_prefix]

  delegation {
    name = "Microsoft.App/environments"
    service_delegation {
      name = "Microsoft.App/environments"
    }
  }
}

# -- Optional APIM subnet (only when provisioning APIM) -----------------------
# NSG for APIM subnet (matches Bicep apimSubnetNsg)
resource "azurerm_network_security_group" "apim" {
  count               = var.deploy_api_management ? 1 : 0
  name                = "${local.vnet_name}-${var.apim_subnet_name}-nsg-${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

# When a new VNet is created we add the APIM subnet to it.
# When an existing VNet is used we only attach the NSG (subnet assumed to exist).
resource "azurerm_subnet" "apim" {
  count                = var.deploy_api_management && !local.existing_vnet_passed_in ? 1 : 0
  name                 = var.apim_subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = [local.effective_apim_subnet_prefix]

  delegation {
    name = "Microsoft.Web/serverFarms"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "apim" {
  count                     = var.deploy_api_management && !local.existing_vnet_passed_in ? 1 : 0
  subnet_id                 = azurerm_subnet.apim[0].id
  network_security_group_id = azurerm_network_security_group.apim[0].id
}

# Effective APIM subnet ID used by the api-management.tf module.
locals {
  apim_subnet_id = var.deploy_api_management ? (
    local.existing_vnet_passed_in ?
    "${local.virtual_network_id}/subnets/${var.apim_subnet_name}" :
    azurerm_subnet.apim[0].id
  ) : ""
}
