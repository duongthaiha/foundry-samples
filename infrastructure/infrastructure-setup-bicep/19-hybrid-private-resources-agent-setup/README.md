# Hybrid Private Resources Agent Setup

This template deploys an Azure AI Foundry account with backend resources (AI Search, Cosmos DB, Storage) on **private endpoints**. By default, the Foundry resource itself also has **public network access disabled**, but this can be switched to public access if needed (see [Switching Between Private and Public Access](#switching-between-private-and-public-access)).

## Architecture (Default — Private Foundry)

```
┌─────────────────────────────────────────────────────────────────────┐
│  Secure Access (VPN Gateway / ExpressRoute / Azure Bastion)         │
└──────────────────────────────────┬──────────────────────────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │      AI Services Account     │
                    │   (publicNetworkAccess:      │
                    │        DISABLED)             │  ◄── Private by default
                    │                              │
                    │  ┌────────────────────────┐  │
                    │  │   Data Proxy / Agent   │  │
                    │  │      ToolServer        │  │
                    │  └───────────┬────────────┘  │
                    └──────────────┼──────────────┘
                                   │ networkInjections
                    ┌──────────────▼──────────────┐
                    │     Private VNet             │
                    │                              │
                    │  ┌─────────┐ ┌─────────┐    │
                    │  │AI Search│ │Cosmos DB│    │  ◄── Private endpoints
                    │  └─────────┘ └─────────┘    │      (no public access)
                    │                              │
                    │  ┌─────────┐ ┌─────────┐    │
                    │  │ Storage │ │   MCP   │    │
                    │  └─────────┘ │ Servers │    │
                    │              └─────────┘    │
                    │  ┌─────────┐                │
                    │  │  APIM   │                │  ◄── Optional (existing)
                    │  │(Gateway)│                │
                    │  └─────────┘                │
                    └─────────────────────────────┘
```

## Key Features

| Feature | This Template (19) — Private (default) | This Template (19) — Public | Fully Private (15) |
|---------|----------------------------------------|-----------------------------|-----------------------|
| AI Services public access | ❌ Disabled | ✅ Enabled | ❌ Disabled |
| Portal access | Via VPN/ExpressRoute/Bastion | ✅ Works directly | Via VPN/ExpressRoute/Bastion |
| Backend resources | 🔒 Private | 🔒 Private | 🔒 Private |
| Data Proxy | ✅ Configured | ✅ Configured | ✅ Configured |
| Secure connection required | ✅ Yes | ❌ No | ✅ Yes |

## Switching Between Private and Public Access

The Foundry resource has **public network access disabled by default**. You can switch between the two modes by modifying the Bicep template.

### To enable public access

In [modules-network-secured/ai-account-identity.bicep](modules-network-secured/ai-account-identity.bicep), change:

```bicep
// Change from:
publicNetworkAccess: 'Disabled'
// To:
publicNetworkAccess: 'Enabled'

// Also change:
defaultAction: 'Deny'
// To:
defaultAction: 'Allow'
```

This makes the Foundry resource accessible from the internet (e.g., for portal-based development without VPN).

### To disable public access (default)

Revert the changes above, setting `publicNetworkAccess: 'Disabled'` and `defaultAction: 'Deny'`.

## Connecting to a Private Foundry Resource

When public network access is disabled (the default), you need a secure connection to reach the Foundry resource. Azure provides three methods:

1. **Azure VPN Gateway** — Connect from your local network to the Azure VNet over an encrypted tunnel.
2. **Azure ExpressRoute** — Use a private, dedicated connection from your on-premises infrastructure to Azure.
3. **Azure Bastion** — Use a jump box VM on the VNet, accessed securely through the Azure portal.

For detailed setup instructions, see: [Securely connect to Azure AI Foundry](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/configure-private-link?view=foundry#securely-connect-to-foundry).

## When to Use This Template

Use this template when you want:
- **Private backend resources** — Keep AI Search, Cosmos DB, and Storage behind private endpoints
- **MCP server integration** — Deploy MCP servers on the VNet that agents can access via Data Proxy
- **APIM integration** — Connect an existing Azure API Management instance via private endpoint for AI gateway scenarios
- **Private Foundry (default)** — Full network isolation with secure access via VPN/ExpressRoute/Bastion
- **Optional public Foundry access** — Switch to public for portal-based development if allowed by your security policy

## When NOT to Use This Template

Use [template 15](../15-private-network-standard-agent-setup/) instead when you need:
- **Fully managed private networking** — Including managed VNet with Microsoft-managed private endpoints
- **Compliance requirements** — Regulations that require a different private networking topology

## Deployment

### Prerequisites

1. Azure CLI installed and authenticated
2. Owner or Contributor role on the subscription
3. Sufficient quota for model deployment (gpt-4o-mini)

### Deploy

```bash
# Create resource group
az group create --name "rg-hybrid-agent-test" --location "westus2"

# Deploy the template
az deployment group create \
  --resource-group "rg-hybrid-agent-test" \
  --template-file main.bicep \
  --parameters location="westus2"
```

### Deploy with APIM

To provision a new API Management instance alongside the agent setup:

```bash
az deployment group create \
  --resource-group "rg-hybrid-agent-test" \
  --template-file main.bicep \
  --parameters location="westus2" deployApiManagement=true publisherEmail="admin@yourorg.com" publisherName="YourOrg"
```

To use an existing APIM instance:

```bash
az deployment group create \
  --resource-group "rg-hybrid-agent-test" \
  --template-file main.bicep \
  --parameters location="westus2" apiManagementResourceId="/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ApiManagement/service/{name}"
```

> **Note:** Only `StandardV2` and `PremiumV2` APIM SKUs support private endpoints. The default is `StandardV2`.

### Verify Deployment

```bash
# Check deployment status
az deployment group show \
  --resource-group "rg-hybrid-agent-test" \
  --name "main" \
  --query "properties.provisioningState"

# List private endpoints (should see AI Search, Storage, Cosmos DB)
az network private-endpoint list \
  --resource-group "rg-hybrid-agent-test" \
  --output table
```

## Testing Agents with Private Resources

### Option 1: Portal Testing

If the Foundry resource has **public network access enabled**, you can test directly in the portal:

1. Navigate to [Azure AI Foundry portal](https://ai.azure.com)
2. Select your project
3. Create an agent with AI Search tool
4. Test that the agent can query the private AI Search index

If the Foundry resource has **public network access disabled** (default), you need to connect via VPN Gateway, ExpressRoute, or Azure Bastion before accessing the portal. See [Connecting to a Private Foundry Resource](#connecting-to-a-private-foundry-resource).

### Option 2: SDK Testing

See [tests/TESTING-GUIDE.md](tests/TESTING-GUIDE.md) for detailed SDK testing instructions.

## MCP Server Deployment

To deploy MCP servers on the private VNet:

```bash
# Create Container Apps environment on mcp-subnet
az containerapp env create \
  --resource-group "rg-hybrid-agent-test" \
  --name "mcp-env" \
  --location "westus2" \
  --infrastructure-subnet-resource-id "<mcp-subnet-resource-id>" \
  --internal-only true

# Deploy MCP server
az containerapp create \
  --resource-group "rg-hybrid-agent-test" \
  --name "my-mcp-server" \
  --environment "mcp-env" \
  --image "<your-mcp-image>" \
  --target-port 8080 \
  --ingress external \
  --min-replicas 1
```

Then configure private DNS zone for Container Apps (see TESTING-GUIDE.md Step 6.3).

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `location` | Azure region | `eastus2` |
| `aiServices` | Base name for AI Services | `aiservices` |
| `modelName` | Model to deploy | `gpt-4o-mini` |
| `modelCapacity` | TPM capacity | `30` |
| `vnetName` | VNet name | `agent-vnet-test` |
| `agentSubnetName` | Subnet for AI Foundry (reserved) | `agent-subnet` |
| `peSubnetName` | Subnet for private endpoints | `pe-subnet` |
| `mcpSubnetName` | Subnet for MCP servers | `mcp-subnet` |
| `apiManagementResourceId` | Existing APIM resource ID (optional) | `''` |
| `deployApiManagement` | Set to true to provision APIM | `false` |
| `apiManagementSku` | APIM SKU (`StandardV2` or `PremiumV2`) | `StandardV2` |
| `publisherEmail` | APIM publisher email | `apim-admin@contoso.com` |
| `publisherName` | APIM publisher name | `AI Foundry` |
| `apimSubnetName` | Subnet for APIM outbound VNet integration | `apim-subnet` |
| `apimSubnetPrefix` | Address prefix for APIM subnet | `192.168.3.0/24` |
| `apimConnectionName` | Name for the APIM gateway connection | `apim-gateway` |
| `apimInferenceApiVersion` | API version for inference calls | `2024-10-21` |
| `apimModelDeployments` | Static model list for the gateway | Uses template model |
| `deployApplicationInsights` | Deploy Application Insights for tracing | `true` |
| `deployBastion` | Deploy Bastion + jump box VM | `false` |
| `bastionSubnetPrefix` | Address prefix for AzureBastionSubnet | `192.168.4.0/26` |
| `jumpboxAdminPassword` | Admin password for jump box VM | (required if Bastion deployed) |
| `deployCrossRegionOpenAI` | Deploy Azure OpenAI in a different region | `false` |
| `crossRegionLocation` | Region for cross-region OpenAI | `westus` |
| `crossRegionModelName` | Model to deploy cross-region | `gpt-4o` |

## APIM AI Gateway

When APIM is deployed (`deployApiManagement=true`) or an existing APIM is provided (`apiManagementResourceId`), the template automatically:
1. Imports the Azure OpenAI inference API into APIM
2. Creates an `ApiManagement` gateway connection on the project with static model metadata
3. Configures private endpoint + DNS for secure inbound access
4. Sets up outbound VNet integration for backend connectivity

After deployment, agents can route requests through the APIM gateway using model name format `<connection-name>/<model-name>`:

```python
# Example: Use APIM gateway model in an agent
FOUNDRY_MODEL_DEPLOYMENT_NAME = "apim-gateway/gpt-4o-mini"
```

For testing, see `tests/test_apim_gateway_agents_v2.py`:
```bash
export PROJECT_ENDPOINT="https://<ai-services>.services.ai.azure.com/api/projects/<project>"
python tests/test_apim_gateway_agents_v2.py
```

For more details, see:
- [AI Gateway docs](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/ai-gateway)
- [APIM Integration Guide](https://github.com/azure-ai-foundry/foundry-samples/blob/main/infrastructure/infrastructure-setup-bicep/01-connections/apim-and-modelgateway-integration-guide.md)

## Cleanup

```bash
# Delete all resources
az group delete --name "rg-hybrid-agent-test" --yes --no-wait
```

## Related Templates

- [15-private-network-standard-agent-setup](../15-private-network-standard-agent-setup/) - Fully private setup (no public access)
- [40-basic-agent-setup](../40-basic-agent-setup/) - Basic agent setup without private networking
- [41-standard-agent-setup](../41-standard-agent-setup/) - Standard agent setup without private networking
