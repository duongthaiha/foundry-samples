/*
  Deploy APIM Developer SKU with VNet Injection in a separate VNet
  and peer it to the existing Agent VNet.
*/

@description('Location for all resources')
param location string = resourceGroup().location

@description('Name for the APIM instance')
param apimName string = 'apim-agent'

@description('Publisher email for APIM (required)')
param publisherEmail string = 'admin@contoso.com'

@description('Publisher name for APIM (required)')
param publisherName string = 'Contoso'

@description('Name of the APIM VNet')
param apimVnetName string = 'apim-vnet'

@description('Address prefix for the APIM VNet')
param apimVnetAddressPrefix string = '10.0.0.0/16'

@description('Name of the APIM subnet')
param apimSubnetName string = 'apim-subnet'

@description('Address prefix for the APIM subnet')
param apimSubnetAddressPrefix string = '10.0.0.0/24'

@description('Resource group containing the existing Agent VNet')
param agentVnetResourceGroup string = resourceGroup().name

@description('Name of the existing Agent VNet to peer with')
param agentVnetName string = 'agent-vnet-test'

// Unique suffix
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 4)
var apimServiceName = toLower('${apimName}-${uniqueSuffix}')

// NSG for APIM subnet - required for VNet injection
resource apimNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${apimVnetName}-apim-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowAPIMManagement'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3443'
          sourceAddressPrefix: 'ApiManagement'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'AllowAzureLoadBalancer'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '6390'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'AllowHTTPS'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'AllowStorageOutbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
        }
      }
      {
        name: 'AllowAADOutbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureActiveDirectory'
        }
      }
      {
        name: 'AllowSQLOutbound'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Sql'
        }
      }
      {
        name: 'AllowAzureMonitorOutbound'
        properties: {
          priority: 130
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: ['443', '1886', '12000']
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureMonitor'
        }
      }
    ]
  }
}

// APIM VNet
resource apimVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: apimVnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [apimVnetAddressPrefix]
    }
    subnets: [
      {
        name: apimSubnetName
        properties: {
          addressPrefix: apimSubnetAddressPrefix
          networkSecurityGroup: {
            id: apimNsg.id
          }
        }
      }
    ]
  }
}

// Reference existing Agent VNet
resource agentVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: agentVnetName
  scope: resourceGroup(agentVnetResourceGroup)
}

// Peering: APIM VNet -> Agent VNet
resource apimToAgentPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: apimVnet
  name: 'apim-to-agent-peering'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: agentVnet.id
    }
  }
}

// Peering: Agent VNet -> APIM VNet
module agentToApimPeering 'modules-network-secured/agent-to-apim-peering.bicep' = {
  name: 'agent-to-apim-peering-deployment'
  scope: resourceGroup(agentVnetResourceGroup)
  params: {
    agentVnetName: agentVnetName
    apimVnetId: apimVnet.id
  }
}

// APIM Developer SKU with VNet injection (internal mode)
resource apimService 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimServiceName
  location: location
  sku: {
    name: 'Developer'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: apimVnet.properties.subnets[0].id
    }
  }
  dependsOn: [
    apimToAgentPeering
    agentToApimPeering
  ]
}

output apimResourceId string = apimService.id
output apimName string = apimService.name
