# -----------------------------------------------------------------------------
# Bastion + Jumpbox VM (optional)
# Mirrors Bicep: modules-network-secured/bastion-jumpbox.bicep
# -----------------------------------------------------------------------------

locals {
  effective_bastion_subnet_prefix = var.bastion_subnet_prefix != "" ? var.bastion_subnet_prefix : cidrsubnet(local.effective_vnet_address_prefix, 10, 16) # /26 style: default 192.168.4.0/26
  effective_jumpbox_subnet_prefix = var.jumpbox_subnet_prefix != "" ? var.jumpbox_subnet_prefix : cidrsubnet(local.effective_vnet_address_prefix, 8, 6)
}

# ---- NAT Gateway public IP --------------------------------------------------
resource "azurerm_public_ip" "nat" {
  count               = var.deploy_bastion ? 1 : 0
  name                = "${var.vm_name}-nat-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "nat" {
  count                   = var.deploy_bastion ? 1 : 0
  name                    = "${var.vm_name}-nat-gw"
  location                = var.location
  resource_group_name     = azurerm_resource_group.rg.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
}

resource "azurerm_nat_gateway_public_ip_association" "nat" {
  count                = var.deploy_bastion ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.nat[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

# ---- Bastion subnet ---------------------------------------------------------
resource "azurerm_subnet" "bastion" {
  count                = var.deploy_bastion ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = local.existing_vnet_passed_in ? local.vnet_rg : azurerm_resource_group.rg.name
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.bastion_subnet_prefix != "" ? var.bastion_subnet_prefix : "192.168.4.0/26"]

  depends_on = [azurerm_virtual_network.vnet]
}

# ---- Bastion public IP ------------------------------------------------------
resource "azurerm_public_ip" "bastion" {
  count               = var.deploy_bastion ? 1 : 0
  name                = "${var.bastion_name}-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ---- Bastion host -----------------------------------------------------------
resource "azurerm_bastion_host" "bastion" {
  count               = var.deploy_bastion ? 1 : 0
  name                = var.bastion_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Basic"

  ip_configuration {
    name                 = "bastion-ipconfig"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}

# ---- Jumpbox subnet (with NAT gateway) --------------------------------------
resource "azurerm_subnet" "jumpbox" {
  count                = var.deploy_bastion ? 1 : 0
  name                 = var.jumpbox_subnet_name
  resource_group_name  = local.existing_vnet_passed_in ? local.vnet_rg : azurerm_resource_group.rg.name
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.jumpbox_subnet_prefix != "" ? var.jumpbox_subnet_prefix : "192.168.6.0/24"]

  depends_on = [azurerm_subnet.bastion]
}

resource "azurerm_subnet_nat_gateway_association" "jumpbox" {
  count          = var.deploy_bastion ? 1 : 0
  subnet_id      = azurerm_subnet.jumpbox[0].id
  nat_gateway_id = azurerm_nat_gateway.nat[0].id
}

# ---- Jumpbox VM NIC ---------------------------------------------------------
resource "azurerm_network_interface" "jumpbox" {
  count               = var.deploy_bastion ? 1 : 0
  name                = "${var.vm_name}-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.jumpbox[0].id
    private_ip_address_allocation = "Dynamic"
  }
}

# ---- Jumpbox Windows VM -----------------------------------------------------
resource "azurerm_windows_virtual_machine" "jumpbox" {
  count                 = var.deploy_bastion ? 1 : 0
  name                  = var.vm_name
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = var.vm_size
  admin_username        = var.vm_admin_username
  admin_password        = var.vm_admin_password
  network_interface_ids = [azurerm_network_interface.jumpbox[0].id]
  computer_name         = var.vm_name

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-24h2-pro"
    version   = "latest"
  }
}
