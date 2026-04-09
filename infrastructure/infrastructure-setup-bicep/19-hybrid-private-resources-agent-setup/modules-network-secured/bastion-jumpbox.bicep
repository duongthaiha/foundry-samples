/*
Bastion and Jump Box Module
----------------------------
Creates Azure Bastion + a Windows VM jump box for accessing private resources
via the Azure portal. This enables debugging and portal access without VPN.

Requirements:
- AzureBastionSubnet (/26 minimum)
- Standard SKU public IP for Bastion
- VM in a subnet that can reach private endpoints
*/

@description('Azure region for the deployment')
param location string

@description('VNet name to deploy into')
param vnetName string

@description('Address prefix for AzureBastionSubnet (minimum /26)')
param bastionSubnetPrefix string = '192.168.4.0/26'

@description('Subnet to place the jump box VM in (must have access to private endpoints)')
param vmSubnetName string = 'pe-subnet'

@description('Name for the Bastion host')
param bastionName string = 'bastion'

@description('Name for the jump box VM')
param vmName string = 'jumpbox'

@description('VM size')
param vmSize string = 'Standard_B2s'

@description('Admin username for the VM')
param adminUsername string = 'azureuser'

@description('Admin password for the VM')
@secure()
param adminPassword string

// ---- NAT Gateway for outbound internet ----
resource natGatewayPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${vmName}-nat-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource natGateway 'Microsoft.Network/natGateways@2024-05-01' = {
  name: '${vmName}-nat-gw'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 10
    publicIpAddresses: [
      {
        id: natGatewayPip.id
      }
    ]
  }
}

// ---- Bastion Subnet ----
resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  name: '${vnetName}/AzureBastionSubnet'
  properties: {
    addressPrefix: bastionSubnetPrefix
  }
}

// ---- Bastion Public IP ----
resource bastionPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${bastionName}-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// ---- Bastion Host ----
resource bastionHost 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: bastionName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'bastion-ipconfig'
        properties: {
          subnet: {
            id: bastionSubnet.id
          }
          publicIPAddress: {
            id: bastionPip.id
          }
        }
      }
    ]
  }
}

// ---- Jump Box VM NIC ----
resource existingVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
}

resource vmSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  name: vmSubnetName
  parent: existingVnet
}

// Attach NAT gateway to VM subnet for outbound internet
resource vmSubnetWithNat 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  name: vmSubnetName
  parent: existingVnet
  properties: {
    addressPrefix: vmSubnet.properties.addressPrefix
    natGateway: {
      id: natGateway.id
    }
    networkSecurityGroup: vmSubnet.properties.networkSecurityGroup
  }
  dependsOn: [
    bastionSubnet
  ]
}

resource vmNic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vmSubnetWithNat.id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
  dependsOn: [
    bastionSubnet
  ]
}

// ---- Jump Box VM ----
resource jumpboxVm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer: 'windows-11'
        sku: 'win11-24h2-pro'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: vmNic.id
        }
      ]
    }
  }
}

output bastionName string = bastionHost.name
output vmName string = jumpboxVm.name
output vmPrivateIp string = vmNic.properties.ipConfigurations[0].properties.privateIPAddress
