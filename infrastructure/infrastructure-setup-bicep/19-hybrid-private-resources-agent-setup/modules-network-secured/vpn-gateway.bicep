/*
VPN Gateway Module
-------------------
Creates an Azure VPN Gateway for secure site-to-site or point-to-site
connectivity to the private VNet. This enables on-premises access to
private resources without exposing them to the internet.

Requirements:
- GatewaySubnet (/27 minimum)
- Standard SKU public IP for the gateway
- VPN Gateway provisioning takes 30-45 minutes
*/

@description('Azure region for the deployment')
param location string

@description('VNet name to deploy the gateway into')
param vnetName string

@description('Address prefix for GatewaySubnet (minimum /27)')
param gatewaySubnetPrefix string = '192.168.255.0/27'

@description('Name for the VPN Gateway')
param gatewayName string = 'vpn-gateway'

@description('SKU for the VPN Gateway')
@allowed([
  'VpnGw1'
  'VpnGw2'
  'VpnGw3'
  'VpnGw1AZ'
  'VpnGw2AZ'
  'VpnGw3AZ'
])
param gatewaySku string = 'VpnGw1'

@description('VPN type')
@allowed([
  'RouteBased'
  'PolicyBased'
])
param vpnType string = 'RouteBased'

// ---- GatewaySubnet ----
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
}

resource gatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  name: 'GatewaySubnet'
  parent: vnet
  properties: {
    addressPrefix: gatewaySubnetPrefix
  }
}

// ---- VPN Gateway Public IP ----
resource gatewayPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${gatewayName}-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// ---- VPN Gateway ----
resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = {
  name: gatewayName
  location: location
  properties: {
    gatewayType: 'Vpn'
    vpnType: vpnType
    sku: {
      name: gatewaySku
      tier: gatewaySku
    }
    ipConfigurations: [
      {
        name: 'vnetGatewayConfig0'
        properties: {
          publicIPAddress: {
            id: gatewayPip.id
          }
          subnet: {
            id: gatewaySubnet.id
          }
        }
      }
    ]
  }
}

output gatewayName string = vpnGateway.name
output gatewayId string = vpnGateway.id
output publicIpAddress string = gatewayPip.properties.ipAddress
