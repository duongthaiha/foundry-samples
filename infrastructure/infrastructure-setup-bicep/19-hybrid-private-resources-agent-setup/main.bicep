/*
Hybrid Private Resources Setup for Azure AI Foundry Agents
-----------------------------------------------------------
This template creates an Azure AI Foundry account with public network access DISABLED,
while keeping backend resources (AI Search, Cosmos DB, Storage) on private endpoints.

Key differences from template 15 (fully private):
- AI Services: publicNetworkAccess = Disabled (default)
- Backend resources: Still private (AI Search, Cosmos DB, Storage)
- Data Proxy: networkInjections configured to route to private VNet

This enables:
✓ Agents can use AI Search tool (routed via Data Proxy to private endpoint)
✓ Agents can use MCP servers running on the VNet

Architecture:
  Private VNet → AI Services (private) → Data Proxy → Private VNet → Backend Resources
*/
@description('Location for all resources.')
param location string = 'eastus2'

@description('Name for your AI Services resource.')
param aiServices string = 'aiservices'

// Model deployment parameters
@description('The name of the model you want to deploy')
param modelName string = 'gpt-4o-mini'
@description('The provider of your model')
param modelFormat string = 'OpenAI'
@description('The version of your model')
param modelVersion string = '2024-07-18'
@description('The sku of your model deployment')
param modelSkuName string = 'GlobalStandard'
@description('The tokens per minute (TPM) of your model deployment')
param modelCapacity int = 30

// Create a short, unique suffix, that will be unique to each resource group
// Uses only resourceGroup().id so the suffix is stable across redeployments
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 4)
var accountName = toLower('${aiServices}${uniqueSuffix}')

@description('Name for your project resource.')
param firstProjectName string = 'project'

@description('This project will be a sub-resource of your account')
param projectDescription string = 'A project for the AI Foundry account with network secured deployed Agent'

@description('The display name of the project')
param displayName string = 'network secured agent project'

// Existing Virtual Network parameters
@description('Virtual Network name for the Agent to create new or existing virtual network')
param vnetName string = 'agent-vnet-test'

@description('The name of Agents Subnet to create new or existing subnet for agents')
param agentSubnetName string = 'agent-subnet'

@description('The name of Private Endpoint subnet to create new or existing subnet for private endpoints')
param peSubnetName string = 'pe-subnet'

@description('The name of MCP subnet for user-deployed Container Apps (e.g., MCP servers)')
param mcpSubnetName string = 'mcp-subnet'

//Existing standard Agent required resources
@description('Existing Virtual Network name Resource ID')
param existingVnetResourceId string = ''

@description('Address space for the VNet (only used for new VNet)')
param vnetAddressPrefix string = ''

@description('Address prefix for the agent subnet. The default value is 192.168.0.0/24 but you can choose any size /26 or any class like 10.0.0.0 or 172.168.0.0')
param agentSubnetPrefix string = ''

@description('Address prefix for the private endpoint subnet')
param peSubnetPrefix string = ''

@description('Address prefix for the MCP subnet. The default value is 192.168.2.0/24.')
param mcpSubnetPrefix string = ''

@description('The name of the APIM subnet for outbound VNet integration (only used when deployApiManagement is true)')
param apimSubnetName string = 'apim-subnet'

@description('Address prefix for the APIM subnet. The default value is 192.168.3.0/24.')
param apimSubnetPrefix string = ''

@description('The AI Search Service full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param aiSearchResourceId string = ''
@description('The AI Storage Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param azureStorageAccountResourceId string = ''
@description('The Cosmos DB Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param azureCosmosDBAccountResourceId string = ''

@description('The Microsoft Fabric Workspace full ARM Resource ID. This is an optional field for Fabric private link connectivity.')
param fabricWorkspaceResourceId string = ''

@description('The API Management Service full ARM Resource ID. This is an optional field for existing API Management services.')
param apiManagementResourceId string = ''

@description('Set to true to deploy an API Management service. If apiManagementResourceId is also provided, the existing resource will be used instead.')
param deployApiManagement bool = false

@description('The SKU of the API Management service. Only StandardV2 and PremiumV2 support private endpoints.')
@allowed([
  'StandardV2'
  'PremiumV2'
])
param apiManagementSku string = 'StandardV2'

@description('The capacity (scale units) of the API Management service')
param apiManagementCapacity int = 1

@description('Publisher email for the API Management service (required when deployApiManagement is true)')
param publisherEmail string = 'apim-admin@contoso.com'

@description('Publisher name for the API Management service (required when deployApiManagement is true)')
param publisherName string = 'AI Foundry'

@description('Name for the APIM gateway connection on the project')
param apimConnectionName string = 'apim-gateway'

@description('API version for inference calls through APIM (chat completions)')
param apimInferenceApiVersion string = '2024-10-21'

@description('Static model deployments to expose through the APIM gateway. Each item needs name, properties.model.name, properties.model.version, properties.model.format.')
param apimModelDeployments array = []

@description('Set to true to deploy Application Insights for agent tracing and logging.')
param deployApplicationInsights bool = true

@description('Set to true to deploy Azure Bastion and a jump box VM for portal access to private resources.')
param deployBastion bool = false

@description('Address prefix for AzureBastionSubnet (minimum /26)')
param bastionSubnetPrefix string = '192.168.4.0/26'

@description('Address prefix for the jump box subnet')
param jumpboxSubnetPrefix string = '192.168.6.0/24'

@description('Admin password for the jump box VM (required when deployBastion is true)')
@secure()
param jumpboxAdminPassword string = ''

@description('Set to true to deploy a VPN Gateway for site-to-site or point-to-site connectivity to the private VNet.')
param deployVpnGateway bool = false

@description('Address prefix for GatewaySubnet (minimum /27)')
param gatewaySubnetPrefix string = '192.168.255.0/27'

@description('SKU for the VPN Gateway')
@allowed([
  'VpnGw1'
  'VpnGw2'
  'VpnGw3'
  'VpnGw1AZ'
  'VpnGw2AZ'
  'VpnGw3AZ'
])
param vpnGatewaySku string = 'VpnGw1'

@description('Set to true to deploy an Azure OpenAI resource in a different region and connect it to the Foundry account.')
param deployCrossRegionOpenAI bool = false

@description('Azure region for the cross-region Azure OpenAI resource (required when deployCrossRegionOpenAI is true)')
param crossRegionLocation string = ''

@description('Model name to deploy in the cross-region OpenAI resource')
param crossRegionModelName string = 'gpt-4o'

@description('Model version for the cross-region deployment')
param crossRegionModelVersion string = '2024-11-20'

@description('Set to true to deploy the marketing pipeline workflow with published application.')
param deployWorkflow bool = false

@description('Set to true to deploy Teams publishing infrastructure (App Gateway, Bot Service, Teams Channel).')
param deployTeamsPublishing bool = false

@description('Custom domain for the Bot messaging endpoint (e.g., agent.yourcompany.com). Required when deployTeamsPublishing is true.')
param teamsCustomDomain string = ''

@description('Name of the agent to publish to Teams')
param teamsAgentName string = 'marketing-pipeline'

@description('Name for the Teams Agent Application')
param teamsApplicationName string = 'marketing-pipeline-teams'

@description('Address prefix for the Application Gateway subnet')
param appGwSubnetPrefix string = '192.168.5.0/24'

//New Param for resource group of Private DNS zones
//@description('Optional: Resource group containing existing private DNS zones. If specified, DNS zones will not be created.')
//param existingDnsZonesResourceGroup string = ''

@description('Object mapping DNS zone names to their resource group, or empty string to indicate creation')
param existingDnsZones object = {
  'privatelink.services.ai.azure.com': ''
  'privatelink.openai.azure.com': ''
  'privatelink.cognitiveservices.azure.com': ''
  'privatelink.search.windows.net': ''
  'privatelink.blob.core.windows.net': ''
  'privatelink.documents.azure.com': ''
  'privatelink.analysis.windows.net': ''
  'privatelink.azure-api.net': ''
}

@description('Zone Names for Validation of existing Private Dns Zones')
param dnsZoneNames array = [
  'privatelink.services.ai.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.cognitiveservices.azure.com'
  'privatelink.search.windows.net'
  'privatelink.blob.core.windows.net'
  'privatelink.documents.azure.com'
  'privatelink.analysis.windows.net'
  'privatelink.azure-api.net'
]

var projectName = toLower('${firstProjectName}${uniqueSuffix}')
var cosmosDBName = toLower('${aiServices}${uniqueSuffix}cosmosdb')
var aiSearchName = toLower('${aiServices}${uniqueSuffix}search')
var azureStorageName = toLower('${aiServices}${uniqueSuffix}storage')
var apiManagementServiceName = toLower('${aiServices}${uniqueSuffix}apim')
var appInsightsName = toLower('${aiServices}${uniqueSuffix}appinsights')
var crossRegionOpenAIName = toLower('${aiServices}${uniqueSuffix}openai-${crossRegionLocation}')

// Check if existing resources have been passed in
var storagePassedIn = azureStorageAccountResourceId != ''
var searchPassedIn = aiSearchResourceId != ''
var cosmosPassedIn = azureCosmosDBAccountResourceId != ''
var existingVnetPassedIn = existingVnetResourceId != ''

var acsParts = split(aiSearchResourceId, '/')
var aiSearchServiceSubscriptionId = searchPassedIn ? acsParts[2] : subscription().subscriptionId
var aiSearchServiceResourceGroupName = searchPassedIn ? acsParts[4] : resourceGroup().name

var cosmosParts = split(azureCosmosDBAccountResourceId, '/')
var cosmosDBSubscriptionId = cosmosPassedIn ? cosmosParts[2] : subscription().subscriptionId
var cosmosDBResourceGroupName = cosmosPassedIn ? cosmosParts[4] : resourceGroup().name

var storageParts = split(azureStorageAccountResourceId, '/')
var azureStorageSubscriptionId = storagePassedIn ? storageParts[2] : subscription().subscriptionId
var azureStorageResourceGroupName = storagePassedIn ? storageParts[4] : resourceGroup().name

var vnetParts = split(existingVnetResourceId, '/')
var vnetSubscriptionId = existingVnetPassedIn ? vnetParts[2] : subscription().subscriptionId
var vnetResourceGroupName = existingVnetPassedIn ? vnetParts[4] : resourceGroup().name
var existingVnetName = existingVnetPassedIn ? last(vnetParts) : vnetName
var trimVnetName = trim(existingVnetName)

@description('The name of the project capability host to be created')
param projectCapHost string = 'caphostproj'

// Create Virtual Network and Subnets
module vnet 'modules-network-secured/network-agent-vnet.bicep' = {
  name: 'vnet-${trimVnetName}-${uniqueSuffix}-deployment'
  params: {
    location: location
    vnetName: trimVnetName
    useExistingVnet: existingVnetPassedIn
    existingVnetResourceGroupName: vnetResourceGroupName
    agentSubnetName: agentSubnetName
    peSubnetName: peSubnetName
    mcpSubnetName: mcpSubnetName
    vnetAddressPrefix: vnetAddressPrefix
    agentSubnetPrefix: agentSubnetPrefix
    peSubnetPrefix: peSubnetPrefix
    mcpSubnetPrefix: mcpSubnetPrefix
    existingVnetSubscriptionId: vnetSubscriptionId
  }
}

// Create APIM subnet for outbound VNet integration (only when provisioning APIM)
var defaultApimSubnetPrefix = '192.168.3.0/24'
var resolvedApimSubnetPrefix = !empty(apimSubnetPrefix) ? apimSubnetPrefix : (!empty(vnetAddressPrefix) ? cidrSubnet(vnetAddressPrefix, 24, 3) : defaultApimSubnetPrefix)

resource apimSubnetNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = if (deployApiManagement) {
  name: '${trimVnetName}-${apimSubnetName}-nsg-${location}'
  location: location
}

module apimSubnet 'modules-network-secured/subnet.bicep' = if (deployApiManagement) {
  name: 'apim-subnet-${uniqueSuffix}-deployment'
  scope: resourceGroup(vnetResourceGroupName)
  params: {
    vnetName: vnet.outputs.virtualNetworkName
    subnetName: apimSubnetName
    addressPrefix: resolvedApimSubnetPrefix
    networkSecurityGroupId: deployApiManagement ? apimSubnetNsg.id : ''
    delegations: [
      {
        name: 'Microsoft.Web/serverFarms'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
  }
}

/*
  Create the AI Services account and gpt-4o model deployment
*/
module aiAccount 'modules-network-secured/ai-account-identity.bicep' = {
  name: '${accountName}-${uniqueSuffix}-deployment'
  params: {
    // workspace organization
    accountName: accountName
    location: location
    modelName: modelName
    modelFormat: modelFormat
    modelVersion: modelVersion
    modelSkuName: modelSkuName
    modelCapacity: modelCapacity
    agentSubnetId: vnet.outputs.agentSubnetId
  }
}

// Deploy Application Insights for agent tracing and logging
module applicationInsights 'modules-network-secured/application-insights.bicep' = if (deployApplicationInsights) {
  name: 'appinsights-${uniqueSuffix}-deployment'
  params: {
    location: location
    accountName: aiAccount.outputs.accountName
    appInsightsName: appInsightsName
  }
}

/*
  Validate existing resources
  This module will check if the AI Search Service, Storage Account, and Cosmos DB Account already exist.
  If they do, it will set the corresponding output to true. If they do not exist, it will set the output to false.
*/
module validateExistingResources 'modules-network-secured/validate-existing-resources.bicep' = {
  name: 'validate-existing-resources-${uniqueSuffix}-deployment'
  params: {
    aiSearchResourceId: aiSearchResourceId
    azureStorageAccountResourceId: azureStorageAccountResourceId
    azureCosmosDBAccountResourceId: azureCosmosDBAccountResourceId
    apiManagementResourceId: apiManagementResourceId
    existingDnsZones: existingDnsZones
    dnsZoneNames: dnsZoneNames
  }
}

// This module will create new agent dependent resources
// A Cosmos DB account, an AI Search Service, and a Storage Account are created if they do not already exist
module aiDependencies 'modules-network-secured/standard-dependent-resources.bicep' = {
  name: 'dependencies-${uniqueSuffix}-deployment'
  params: {
    location: location
    azureStorageName: azureStorageName
    aiSearchName: aiSearchName
    cosmosDBName: cosmosDBName

    // AI Search Service parameters
    aiSearchResourceId: aiSearchResourceId
    aiSearchExists: validateExistingResources.outputs.aiSearchExists

    // Storage Account
    azureStorageAccountResourceId: azureStorageAccountResourceId
    azureStorageExists: validateExistingResources.outputs.azureStorageExists

    // Cosmos DB Account
    cosmosDBResourceId: azureCosmosDBAccountResourceId
    cosmosDBExists: validateExistingResources.outputs.cosmosDBExists
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2022-05-01' existing = {
  name: aiDependencies.outputs.azureStorageName
  scope: resourceGroup(azureStorageSubscriptionId, azureStorageResourceGroupName)
}

resource aiSearch 'Microsoft.Search/searchServices@2023-11-01' existing = {
  name: aiDependencies.outputs.aiSearchName
  scope: resourceGroup(
    aiDependencies.outputs.aiSearchServiceSubscriptionId,
    aiDependencies.outputs.aiSearchServiceResourceGroupName
  )
}

resource cosmosDB 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: aiDependencies.outputs.cosmosDBName
  scope: resourceGroup(cosmosDBSubscriptionId, cosmosDBResourceGroupName)
}

// Conditionally create or reference an existing API Management service
module apimDependencies 'modules-network-secured/api-management.bicep' = if (deployApiManagement) {
  name: 'apim-${uniqueSuffix}-deployment'
  params: {
    location: location
    apiManagementName: apiManagementServiceName
    apiManagementSku: apiManagementSku
    apiManagementCapacity: apiManagementCapacity
    publisherEmail: publisherEmail
    publisherName: publisherName
    apimSubnetId: deployApiManagement ? apimSubnet.outputs.subnetId : ''
    apiManagementResourceId: apiManagementResourceId
    apiManagementExists: validateExistingResources.outputs.apiManagementExists
  }
}

// Compute the final APIM name and location info from either the provisioning module or validation
var resolvedApiManagementName = deployApiManagement ? apimDependencies.outputs.apiManagementName : validateExistingResources.outputs.apiManagementName
var resolvedApiManagementResourceGroupName = deployApiManagement ? apimDependencies.outputs.apiManagementResourceGroupName : validateExistingResources.outputs.apiManagementResourceGroupName
var resolvedApiManagementSubscriptionId = deployApiManagement ? apimDependencies.outputs.apiManagementSubscriptionId : validateExistingResources.outputs.apiManagementSubscriptionId

// Private Endpoint and DNS Configuration
// This module sets up private network access for all Azure services:
// 1. Creates private endpoints in the specified subnet
// 2. Sets up private DNS zones for each service
// 3. Links private DNS zones to the VNet for name resolution
// 4. Configures network policies to restrict access to private endpoints only
module privateEndpointAndDNS 'modules-network-secured/private-endpoint-and-dns.bicep' = {
  name: '${uniqueSuffix}-private-endpoint'
  params: {
    aiAccountName: aiAccount.outputs.accountName // AI Services to secure
    aiSearchName: aiDependencies.outputs.aiSearchName // AI Search to secure
    storageName: aiDependencies.outputs.azureStorageName // Storage to secure
    cosmosDBName: aiDependencies.outputs.cosmosDBName
    fabricWorkspaceResourceId: fabricWorkspaceResourceId // Microsoft Fabric workspace (optional)
    apiManagementName: resolvedApiManagementName // API Management to secure (optional)
    vnetName: vnet.outputs.virtualNetworkName // VNet containing subnets
    peSubnetName: vnet.outputs.peSubnetName // Subnet for private endpoints
    suffix: uniqueSuffix // Unique identifier
    vnetResourceGroupName: vnet.outputs.virtualNetworkResourceGroup
    vnetSubscriptionId: vnet.outputs.virtualNetworkSubscriptionId // Subscription ID for the VNet
    cosmosDBSubscriptionId: cosmosDBSubscriptionId // Subscription ID for Cosmos DB
    cosmosDBResourceGroupName: cosmosDBResourceGroupName // Resource Group for Cosmos DB
    aiSearchSubscriptionId: aiSearchServiceSubscriptionId // Subscription ID for AI Search Service
    aiSearchResourceGroupName: aiSearchServiceResourceGroupName // Resource Group for AI Search Service
    storageAccountResourceGroupName: azureStorageResourceGroupName // Resource Group for Storage Account
    storageAccountSubscriptionId: azureStorageSubscriptionId // Subscription ID for Storage Account
    apiManagementResourceGroupName: resolvedApiManagementResourceGroupName // Resource Group for API Management (if provided)
    apiManagementSubscriptionId: resolvedApiManagementSubscriptionId // Subscription ID for API Management (if provided)
    existingDnsZones: existingDnsZones
  }
  dependsOn: [
    aiSearch // Ensure AI Search exists
    storage // Ensure Storage exists
    cosmosDB // Ensure Cosmos DB exists
  ]
}

/*
  Creates a new project (sub-resource of the AI Services account)
*/
module aiProject 'modules-network-secured/ai-project-identity.bicep' = {
  name: '${projectName}-${uniqueSuffix}-deployment'
  params: {
    // workspace organization
    projectName: projectName
    projectDescription: projectDescription
    displayName: displayName
    location: location

    aiSearchName: aiDependencies.outputs.aiSearchName
    aiSearchServiceResourceGroupName: aiDependencies.outputs.aiSearchServiceResourceGroupName
    aiSearchServiceSubscriptionId: aiDependencies.outputs.aiSearchServiceSubscriptionId

    cosmosDBName: aiDependencies.outputs.cosmosDBName
    cosmosDBSubscriptionId: aiDependencies.outputs.cosmosDBSubscriptionId
    cosmosDBResourceGroupName: aiDependencies.outputs.cosmosDBResourceGroupName

    azureStorageName: aiDependencies.outputs.azureStorageName
    azureStorageSubscriptionId: aiDependencies.outputs.azureStorageSubscriptionId
    azureStorageResourceGroupName: aiDependencies.outputs.azureStorageResourceGroupName
    // dependent resources
    accountName: aiAccount.outputs.accountName
  }
  dependsOn: [
    privateEndpointAndDNS
    cosmosDB
    aiSearch
    storage
  ]
}

module formatProjectWorkspaceId 'modules-network-secured/format-project-workspace-id.bicep' = {
  name: 'format-project-workspace-id-${uniqueSuffix}-deployment'
  params: {
    projectWorkspaceId: aiProject.outputs.projectWorkspaceId
  }
}

/*
  Assigns the project SMI the storage blob data contributor role on the storage account
*/
module storageAccountRoleAssignment 'modules-network-secured/azure-storage-account-role-assignment.bicep' = {
  name: 'storage-${azureStorageName}-${uniqueSuffix}-deployment'
  scope: resourceGroup(azureStorageSubscriptionId, azureStorageResourceGroupName)
  params: {
    azureStorageName: aiDependencies.outputs.azureStorageName
    projectPrincipalId: aiProject.outputs.projectPrincipalId
  }
  dependsOn: [
    storage
    privateEndpointAndDNS
  ]
}

// The Comos DB Operator role must be assigned before the caphost is created
module cosmosAccountRoleAssignments 'modules-network-secured/cosmosdb-account-role-assignment.bicep' = {
  name: 'cosmos-account-ra-${uniqueSuffix}-deployment'
  scope: resourceGroup(cosmosDBSubscriptionId, cosmosDBResourceGroupName)
  params: {
    cosmosDBName: aiDependencies.outputs.cosmosDBName
    projectPrincipalId: aiProject.outputs.projectPrincipalId
  }
  dependsOn: [
    cosmosDB
    privateEndpointAndDNS
  ]
}

// This role can be assigned before or after the caphost is created
module aiSearchRoleAssignments 'modules-network-secured/ai-search-role-assignments.bicep' = {
  name: 'ai-search-ra-${uniqueSuffix}-deployment'
  scope: resourceGroup(aiSearchServiceSubscriptionId, aiSearchServiceResourceGroupName)
  params: {
    aiSearchName: aiDependencies.outputs.aiSearchName
    projectPrincipalId: aiProject.outputs.projectPrincipalId
  }
  dependsOn: [
    aiSearch
    privateEndpointAndDNS
  ]
}

/*
  Cross-service RBAC: Search MI → Storage, Search MI → OpenAI, Account MI → Search, Account MI → Storage
  These roles enable knowledge source creation (Foundry IQ) and cross-service data access.
*/

// Search MI needs Storage Blob Data Reader to index blobs for knowledge sources
module searchMiToStorageRoleAssignment 'modules-network-secured/search-mi-to-storage-role-assignment.bicep' = {
  name: 'search-mi-storage-ra-${uniqueSuffix}-deployment'
  scope: resourceGroup(azureStorageSubscriptionId, azureStorageResourceGroupName)
  params: {
    azureStorageName: aiDependencies.outputs.azureStorageName
    searchServicePrincipalId: aiDependencies.outputs.aiSearchPrincipalId
  }
  dependsOn: [
    aiSearch
    storage
    privateEndpointAndDNS
  ]
}

// Search MI needs Cognitive Services OpenAI User to use embedding/chat models during indexing
module searchMiToOpenAIRoleAssignment 'modules-network-secured/search-mi-to-openai-role-assignment.bicep' = {
  name: 'search-mi-openai-ra-${uniqueSuffix}-deployment'
  params: {
    accountName: aiAccount.outputs.accountName
    searchServicePrincipalId: aiDependencies.outputs.aiSearchPrincipalId
  }
  dependsOn: [
    aiSearch
    privateEndpointAndDNS
  ]
}

// Account MI needs Search Index Data Contributor + Search Service Contributor
module accountToSearchRoleAssignment 'modules-network-secured/ai-account-to-search-role-assignment.bicep' = {
  name: 'account-search-ra-${uniqueSuffix}-deployment'
  scope: resourceGroup(aiSearchServiceSubscriptionId, aiSearchServiceResourceGroupName)
  params: {
    aiSearchName: aiDependencies.outputs.aiSearchName
    accountPrincipalId: aiAccount.outputs.accountPrincipalId
  }
  dependsOn: [
    aiSearch
    privateEndpointAndDNS
  ]
}

// Account MI needs Storage Blob Data Contributor
module accountToStorageRoleAssignment 'modules-network-secured/ai-account-to-storage-role-assignment.bicep' = {
  name: 'account-storage-ra-${uniqueSuffix}-deployment'
  scope: resourceGroup(azureStorageSubscriptionId, azureStorageResourceGroupName)
  params: {
    azureStorageName: aiDependencies.outputs.azureStorageName
    accountPrincipalId: aiAccount.outputs.accountPrincipalId
  }
  dependsOn: [
    storage
    privateEndpointAndDNS
  ]
}

// This module creates the capability host for the project and account
module addProjectCapabilityHost 'modules-network-secured/add-project-capability-host.bicep' = {
  name: 'capabilityHost-configuration-${uniqueSuffix}-deployment'
  params: {
    accountName: aiAccount.outputs.accountName
    projectName: aiProject.outputs.projectName
    cosmosDBConnection: aiProject.outputs.cosmosDBConnection
    azureStorageConnection: aiProject.outputs.azureStorageConnection
    aiSearchConnection: aiProject.outputs.aiSearchConnection
    projectCapHost: projectCapHost
  }
  dependsOn: [
    aiSearch // Ensure AI Search exists
    storage // Ensure Storage exists
    cosmosDB
    privateEndpointAndDNS
    cosmosAccountRoleAssignments
    storageAccountRoleAssignment
    aiSearchRoleAssignments
  ]
}

// The Storage Blob Data Owner role must be assigned after the caphost is created
module storageContainersRoleAssignment 'modules-network-secured/blob-storage-container-role-assignments.bicep' = {
  name: 'storage-containers-ra-${uniqueSuffix}-deployment'
  scope: resourceGroup(azureStorageSubscriptionId, azureStorageResourceGroupName)
  params: {
    aiProjectPrincipalId: aiProject.outputs.projectPrincipalId
    storageName: aiDependencies.outputs.azureStorageName
    workspaceId: formatProjectWorkspaceId.outputs.projectWorkspaceIdGuid
  }
  dependsOn: [
    addProjectCapabilityHost
  ]
}

// The Cosmos Built-In Data Contributor role must be assigned after the caphost is created
module cosmosContainerRoleAssignments 'modules-network-secured/cosmos-container-role-assignments.bicep' = {
  name: 'cosmos-containers-ra-${uniqueSuffix}-deployment'
  scope: resourceGroup(cosmosDBSubscriptionId, cosmosDBResourceGroupName)
  params: {
    cosmosAccountName: aiDependencies.outputs.cosmosDBName
    projectWorkspaceId: formatProjectWorkspaceId.outputs.projectWorkspaceIdGuid
    projectPrincipalId: aiProject.outputs.projectPrincipalId
  }
  dependsOn: [
    addProjectCapabilityHost
    storageContainersRoleAssignment
  ]
}

// Create APIM gateway connection on the project (only when APIM is deployed/configured)
var apimConfigured = deployApiManagement || apiManagementResourceId != ''
// Build default model deployments from the template's model params if none provided
var defaultModelDeployments = [
  {
    name: modelName
    properties: {
      model: {
        name: modelName
        version: modelVersion
        format: modelFormat
      }
    }
  }
]
var resolvedModelDeployments = length(apimModelDeployments) > 0 ? apimModelDeployments : defaultModelDeployments

module apimGatewayConnection 'modules-network-secured/apim-gateway-connection.bicep' = if (apimConfigured) {
  name: 'apim-gateway-connection-${uniqueSuffix}-deployment'
  params: {
    accountName: aiAccount.outputs.accountName
    projectName: aiProject.outputs.projectName
    apimName: resolvedApiManagementName
    aiServicesEndpoint: 'https://${aiAccount.outputs.accountName}.openai.azure.com'
    connectionName: apimConnectionName
    inferenceApiVersion: apimInferenceApiVersion
    modelDeployments: resolvedModelDeployments
  }
  dependsOn: [
    addProjectCapabilityHost
    apimDependencies
    privateEndpointAndDNS
  ]
}

// Deploy Azure Bastion and jump box VM for portal access to private resources
module bastionJumpbox 'modules-network-secured/bastion-jumpbox.bicep' = if (deployBastion) {
  name: 'bastion-${uniqueSuffix}-deployment'
  params: {
    location: location
    vnetName: vnet.outputs.virtualNetworkName
    bastionSubnetPrefix: bastionSubnetPrefix
    jumpboxSubnetName: 'jumpbox-subnet'
    jumpboxSubnetPrefix: jumpboxSubnetPrefix
    bastionName: '${accountName}-bastion'
    vmName: '${uniqueSuffix}-jumpbox'
    adminPassword: jumpboxAdminPassword
  }
}

// Deploy VPN Gateway for site-to-site or point-to-site connectivity
module vpnGateway 'modules-network-secured/vpn-gateway.bicep' = if (deployVpnGateway) {
  name: 'vpn-gateway-${uniqueSuffix}-deployment'
  params: {
    location: location
    vnetName: vnet.outputs.virtualNetworkName
    gatewaySubnetPrefix: gatewaySubnetPrefix
    gatewaySku: vpnGatewaySku
  }
}

// Deploy cross-region Azure OpenAI resource and connect to Foundry
module crossRegionOpenAI 'modules-network-secured/cross-region-openai-connection.bicep' = if (deployCrossRegionOpenAI) {
  name: 'cross-region-openai-${uniqueSuffix}-deployment'
  params: {
    location: crossRegionLocation
    accountName: aiAccount.outputs.accountName
    projectName: aiProject.outputs.projectName
    openAIName: crossRegionOpenAIName
    modelName: crossRegionModelName
    modelVersion: crossRegionModelVersion
    apimName: resolvedApiManagementName
    vnetName: vnet.outputs.virtualNetworkName
    peSubnetName: vnet.outputs.peSubnetName
    vnetResourceGroupName: vnet.outputs.virtualNetworkResourceGroup
  }
  dependsOn: [
    aiAccount
    aiProject
    apimDependencies
    addProjectCapabilityHost
    privateEndpointAndDNS
  ]
}

// Deploy marketing pipeline workflow with published application
var workflowAgentModel = deployApiManagement ? 'apim-gateway/${modelName}' : modelName
module workflowDeployment 'modules-network-secured/workflow-deployment.bicep' = if (deployWorkflow) {
  name: 'workflow-${uniqueSuffix}-deployment'
  params: {
    location: location
    accountName: aiAccount.outputs.accountName
    projectName: aiProject.outputs.projectName
    agentModel: workflowAgentModel
  }
  dependsOn: [
    addProjectCapabilityHost
    apimGatewayConnection
  ]
}

// Deploy Teams publishing infrastructure
module teamsPublishScript 'modules-network-secured/teams-agent-publish-script.bicep' = if (deployTeamsPublishing) {
  name: 'teams-publish-${uniqueSuffix}-deployment'
  params: {
    location: location
    accountName: aiAccount.outputs.accountName
    projectName: aiProject.outputs.projectName
    agentName: teamsAgentName
    applicationName: teamsApplicationName
  }
  dependsOn: [
    addProjectCapabilityHost
    workflowDeployment
  ]
}

module teamsInfra 'modules-network-secured/teams-publishing-infra.bicep' = if (deployTeamsPublishing) {
  name: 'teams-infra-${uniqueSuffix}-deployment'
  params: {
    location: location
    vnetName: vnet.outputs.virtualNetworkName
    appGwSubnetPrefix: appGwSubnetPrefix
    apimName: resolvedApiManagementName
    accountName: aiAccount.outputs.accountName
    projectName: aiProject.outputs.projectName
    applicationName: teamsApplicationName
    customDomain: teamsCustomDomain
    botClientId: deployTeamsPublishing ? teamsPublishScript.outputs.botClientId : ''
    activityProtocolUrl: deployTeamsPublishing ? teamsPublishScript.outputs.activityProtocolUrl : ''
    apimPrivateIp: '' // Set to APIM private endpoint IP for fully private deployments
  }
  dependsOn: [
    teamsPublishScript
    apimDependencies
    privateEndpointAndDNS
  ]
}