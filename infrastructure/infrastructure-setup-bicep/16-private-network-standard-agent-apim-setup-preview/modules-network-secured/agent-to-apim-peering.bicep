/*
  Module to create VNet peering from Agent VNet to APIM VNet.
  Deployed as a separate module to support cross-resource-group scope.
*/

@description('Name of the existing Agent VNet')
param agentVnetName string

@description('Resource ID of the APIM VNet to peer with')
param apimVnetId string

resource agentVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: agentVnetName
}

resource agentToApimPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: agentVnet
  name: 'agent-to-apim-peering'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: apimVnetId
    }
  }
}
