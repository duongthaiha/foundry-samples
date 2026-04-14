# Hybrid Private Resources Agent Setup

This template deploys an Azure AI Foundry account with backend resources (AI Search, Cosmos DB, Storage) on **private endpoints**, with optional **APIM AI Gateway**, **cross-region OpenAI**, **Application Insights**, **Azure Bastion**, and **Teams publishing** (with Application Gateway + Bot Service).

By default, the Foundry resource has **public network access disabled**, but this can be switched to public access if needed (see [Switching Between Private and Public Access](#switching-between-private-and-public-access)).

## Architecture

See [diagrams/architecture.md](diagrams/architecture.md) for the full Mermaid infrastructure diagram, and [diagrams/sequence-diagram.md](diagrams/sequence-diagram.md) for agent interaction sequence diagrams.

```
┌─────────────────────────────────────────────────────────────────────┐
│  Secure Access (VPN Gateway / Azure Bastion / ExpressRoute)         │
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
                    │  ┌─────────┐ ┌─────────┐    │
                    │  │  APIM   │ │ Bastion │    │  ◄── Optional
                    │  │(Gateway)│ │+ JumpBox│    │
                    │  └─────────┘ └─────────┘    │
                    │                              │
                    │  ┌──────────────────────┐    │
                    │  │ Cross-Region OpenAI  │    │  ◄── Optional (via PE)
                    │  │    (e.g., westus)    │    │
                    │  └──────────────────────┘    │
                    └─────────────────────────────┘
```

## Key Features

| Feature | Description |
|---------|-------------|
| **Private backend resources** | AI Search, Cosmos DB, Storage behind private endpoints |
| **MCP server integration** | Deploy MCP servers on the VNet via Data Proxy |
| **APIM AI Gateway** | Route agent model requests through APIM with managed identity auth |
| **Cross-region OpenAI** | Access models in different regions via APIM gateway + private endpoints |
| **Application Insights** | Agent tracing and observability with Log Analytics |
| **Azure Bastion + Jump Box** | Portal access to private resources without VPN |
| **VPN Gateway** | Site-to-site or point-to-site VPN connectivity to the private VNet |
| **Private/Public toggle** | Switch Foundry between private and public access |

## Modules

| Module | Description |
|--------|-------------|
| `network-agent-vnet.bicep` | VNet with agent, PE, MCP, APIM, Bastion, and Gateway subnets |
| `ai-account-identity.bicep` | AI Services account with model deployment |
| `ai-project-identity.bicep` | Foundry project with connections (Cosmos DB, Storage, AI Search) |
| `standard-dependent-resources.bicep` | Cosmos DB, AI Search, Storage (create or use existing) |
| `private-endpoint-and-dns.bicep` | Private endpoints + DNS zones for all services (including APIM, Fabric) |
| `api-management.bicep` | APIM StandardV2/PremiumV2 with outbound VNet integration |
| `apim-gateway-connection.bicep` | Import OpenAI API into APIM + create ApiManagement gateway connection |
| `cross-region-openai-connection.bicep` | Cross-region OpenAI + model + APIM API + PE + DNS + gateway connection |
| `application-insights.bicep` | Log Analytics workspace + Application Insights + Foundry connection |
| `bastion-jumpbox.bicep` | Azure Bastion + Windows jump box VM + NAT gateway |
| `vpn-gateway.bicep` | VPN Gateway with GatewaySubnet for site-to-site or point-to-site connectivity |
| `teams-publishing-infra.bicep` | App Gateway WAF v2 + APIM Bot API + Bot Service + Teams Channel + Key Vault |
| `teams-agent-publish-script.bicep` | Deployment script: Agent Application + Deployment for Teams |
| `workflow-deployment.bicep` | Deployment script: workflow agents + Agent Application |
| `validate-existing-resources.bicep` | Validates existing resources (AI Search, Storage, Cosmos DB, APIM) |
| `add-project-capability-host.bicep` | Capability host for agent tools |

## Deployment

### Prerequisites

1. Azure CLI installed and authenticated (`az login`)
2. Bicep CLI installed (`az bicep install`)
3. Owner or Contributor role on the subscription
4. Sufficient quota for model deployments
5. Required resource providers registered:

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.ContainerService
```

### Basic Deploy (Private Foundry)

```bash
az group create --name "rg-hybrid-agent-test" --location "eastus2"

az deployment group create \
  --resource-group "rg-hybrid-agent-test" \
  --template-file main.bicep \
  --parameters location="eastus2"
```

### Deploy with APIM AI Gateway

```bash
# Provision new APIM with gateway connection
az deployment group create \
  --resource-group "rg-hybrid-agent-test" \
  --template-file main.bicep \
  --parameters location="eastus2" \
    deployApiManagement=true \
    publisherEmail="admin@yourorg.com" \
    publisherName="YourOrg"
```

```bash
# Use an existing APIM instance
az deployment group create \
  --resource-group "rg-hybrid-agent-test" \
  --template-file main.bicep \
  --parameters location="eastus2" \
    apiManagementResourceId="/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ApiManagement/service/{name}"
```

> **Note:** Only `StandardV2` and `PremiumV2` APIM SKUs support private endpoints. The default is `StandardV2`.

### Deploy with Cross-Region OpenAI

```bash
az deployment group create \
  --resource-group "rg-hybrid-agent-test" \
  --template-file main.bicep \
  --parameters location="eastus2" \
    deployApiManagement=true \
    publisherEmail="admin@yourorg.com" \
    deployCrossRegionOpenAI=true \
    crossRegionLocation="westus" \
    crossRegionModelName="gpt-4o"
```

### Deploy with Bastion + Jump Box

```bash
az deployment group create \
  --resource-group "rg-hybrid-agent-test" \
  --template-file main.bicep \
  --parameters location="eastus2" \
    deployBastion=true \
    jumpboxAdminPassword="YourSecurePassword123!"
```

Then connect via Azure Portal → VM → Connect → Bastion.

### Deploy with VPN Gateway

```bash
az deployment group create \
  --resource-group "rg-hybrid-agent-test" \
  --template-file main.bicep \
  --parameters location="eastus2" \
    deployVpnGateway=true
```

> **Note:** VPN Gateway provisioning takes 30-45 minutes. The default SKU is `VpnGw1` with RouteBased VPN type.

### Full Deploy (All Features)

```bash
az deployment group create \
  --resource-group "rg-hybrid-agent-test" \
  --template-file main.bicep \
  --parameters location="eastus2" \
    deployApiManagement=true \
    publisherEmail="admin@yourorg.com" \
    deployCrossRegionOpenAI=true \
    crossRegionLocation="westus" \
    deployApplicationInsights=true \
    deployBastion=true \
    jumpboxAdminPassword="YourSecurePassword123!"
```

### Verify Deployment

```bash
az deployment group show \
  --resource-group "rg-hybrid-agent-test" \
  --name "main" \
  --query "properties.provisioningState"

az network private-endpoint list \
  --resource-group "rg-hybrid-agent-test" \
  --output table
```

## APIM AI Gateway

When APIM is deployed, the template automatically:
1. Creates APIM (StandardV2) with outbound VNet integration
2. Imports the Azure OpenAI inference API into APIM
3. Adds managed identity authentication policy (`authentication-managed-identity`)
4. Creates an `ApiManagement` gateway connection on the project with static model metadata
5. Configures private endpoint + DNS for secure inbound access

Agents route requests through the gateway using the model name format `<connection-name>/<model-name>`:

```python
from azure.ai.projects.models import PromptAgentDefinition

# Local model (eastus2) via APIM
agent = client.agents.create_version(
    agent_name="my-agent",
    definition=PromptAgentDefinition(
        model="apim-gateway/gpt-4o-mini",
        instructions="You are a helpful assistant.",
    ),
)

# Cross-region model (westus) via APIM
agent = client.agents.create_version(
    agent_name="cross-region-agent",
    definition=PromptAgentDefinition(
        model="apim-gateway-crossregion/gpt-4o",
        instructions="You are a helpful assistant.",
    ),
)
```

For more details, see:
- [AI Gateway docs](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/ai-gateway)
- [APIM Integration Guide](https://github.com/azure-ai-foundry/foundry-samples/blob/main/infrastructure/infrastructure-setup-bicep/01-connections/apim-and-modelgateway-integration-guide.md)

## Cross-Region OpenAI

When `deployCrossRegionOpenAI=true`, the template creates:
1. Azure OpenAI resource in the specified region (e.g., `westus`) with a model deployment
2. Private endpoint in the primary VNet for secure cross-region connectivity
3. DNS registration in `privatelink.openai.azure.com` for name resolution
4. APIM API pointing to the cross-region backend with managed identity auth
5. APIM gateway connection on the project (`apim-gateway-crossregion/<model>`)

This enables agents in the primary region to use models deployed in other regions, routed securely via the APIM gateway and Azure backbone private links.

## Observability

Application Insights is deployed by default (`deployApplicationInsights=true`), providing:
- **Agent traces** — `invoke_agent` and `chat` metrics in `AppDependencies` table
- **Latency tracking** — per-call duration for agent invocations and model calls
- **Foundry portal tracing** — visible at [ai.azure.com](https://ai.azure.com) → project → Tracing

Query traces via Log Analytics:
```kql
AppDependencies
| where TimeGenerated > ago(1h)
| project TimeGenerated, Name, DurationMs, Success
| order by TimeGenerated desc
```

## Testing

### SDK Testing

```bash
export PROJECT_ENDPOINT="https://<ai-services>.services.ai.azure.com/api/projects/<project>"

# Test basic agent
python tests/test_agents_v2.py

# Test APIM gateway agent
python tests/test_apim_gateway_agents_v2.py

# Test AI Search tool
python tests/test_ai_search_tool_agents_v2.py

# Test MCP tools
python tests/test_mcp_tools_agents_v2.py
```

See [tests/TESTING-GUIDE.md](tests/TESTING-GUIDE.md) for detailed instructions.

### Portal Testing

If public access is enabled, test directly at [ai.azure.com](https://ai.azure.com). If private (default), connect via Bastion jump box or VPN first.

> **Note:** The Foundry portal backend makes server-to-server API calls that don't route through your VPN. For full portal access to private resources, use the Bastion jump box or temporarily enable public access.

## Switching Between Private and Public Access

In [modules-network-secured/ai-account-identity.bicep](modules-network-secured/ai-account-identity.bicep), change:

```bicep
// To enable public access:
publicNetworkAccess: 'Enabled'
defaultAction: 'Allow'

// To disable public access (default):
publicNetworkAccess: 'Disabled'
defaultAction: 'Deny'
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| **Core** | | |
| `location` | Azure region | `eastus2` |
| `aiServices` | Base name for AI Services | `aiservices` |
| `modelName` | Model to deploy | `gpt-4o-mini` |
| `modelCapacity` | TPM capacity | `30` |
| **Networking** | | |
| `vnetName` | VNet name | `agent-vnet-test` |
| `agentSubnetName` | Subnet for AI Foundry (reserved) | `agent-subnet` |
| `peSubnetName` | Subnet for private endpoints | `pe-subnet` |
| `mcpSubnetName` | Subnet for MCP servers | `mcp-subnet` |
| `existingVnetResourceId` | Use existing VNet (optional) | `''` |
| **APIM** | | |
| `deployApiManagement` | Provision APIM | `false` |
| `apiManagementResourceId` | Existing APIM resource ID | `''` |
| `apiManagementSku` | APIM SKU (`StandardV2` / `PremiumV2`) | `StandardV2` |
| `publisherEmail` | APIM publisher email | `apim-admin@contoso.com` |
| `publisherName` | APIM publisher name | `AI Foundry` |
| `apimSubnetName` | Subnet for APIM outbound VNet integration | `apim-subnet` |
| `apimSubnetPrefix` | APIM subnet address prefix | `192.168.3.0/24` |
| `apimConnectionName` | Name for APIM gateway connection | `apim-gateway` |
| `apimInferenceApiVersion` | API version for inference calls | `2024-10-21` |
| `apimModelDeployments` | Static model list for gateway | Uses template model |
| **Cross-Region** | | |
| `deployCrossRegionOpenAI` | Deploy OpenAI in different region | `false` |
| `crossRegionLocation` | Region for cross-region OpenAI | (required if deployed) |
| `crossRegionModelName` | Cross-region model to deploy | `gpt-4o` |
| `crossRegionModelVersion` | Cross-region model version | `2024-11-20` |
| **Workflow** | | |
| `deployWorkflow` | Deploy marketing pipeline workflow | `false` |
| **Teams Publishing** | | |
| `deployTeamsPublishing` | Deploy Teams publishing infrastructure | `false` |
| `teamsCustomDomain` | Custom domain for Bot endpoint | (required if deployed) |
| `teamsAgentName` | Agent to publish to Teams | `marketing-pipeline` |
| `teamsApplicationName` | Teams Agent Application name | `marketing-pipeline-teams` |
| `appGwSubnetPrefix` | Application Gateway subnet prefix | `192.168.5.0/24` |
| `crossRegionModelVersion` | Cross-region model version | `2024-11-20` |
| **Observability** | | |
| `deployApplicationInsights` | Deploy Application Insights | `true` |
| **Bastion** | | |
| `deployBastion` | Deploy Bastion + jump box VM | `false` |
| `bastionSubnetPrefix` | AzureBastionSubnet address prefix | `192.168.4.0/26` |
| `jumpboxAdminPassword` | Jump box admin password | (required if deployed) |
| **VPN Gateway** | | |
| `deployVpnGateway` | Deploy VPN Gateway | `false` |
| `gatewaySubnetPrefix` | GatewaySubnet address prefix | `192.168.255.0/27` |
| `vpnGatewaySku` | VPN Gateway SKU | `VpnGw1` |

## MCP Server Deployment

```bash
az containerapp env create \
  --resource-group "rg-hybrid-agent-test" \
  --name "mcp-env" \
  --location "eastus2" \
  --infrastructure-subnet-resource-id "<mcp-subnet-resource-id>" \
  --internal-only true

az containerapp create \
  --resource-group "rg-hybrid-agent-test" \
  --name "my-mcp-server" \
  --environment "mcp-env" \
  --image "<your-mcp-image>" \
  --target-port 8080 \
  --ingress external \
  --min-replicas 1
```

## Publishing to Microsoft Teams

For publishing agents to Teams while keeping the agent on a private network, see **[PUBLISH.md](PUBLISH.md)** for the complete step-by-step guide.

Deploy with Teams publishing:
```bash
az deployment group create \
  --resource-group "rg-hybrid-agent-test" \
  --template-file main.bicep \
  --parameters \
    deployApiManagement=true \
    deployTeamsPublishing=true \
    teamsCustomDomain="agent.yourcompany.com" \
    deployWorkflow=true
```

This creates Application Gateway (WAF v2), Bot Service, Teams Channel, and APIM JWT validation — all keeping the agent private.

## Cleanup

```bash
az group delete --name "rg-hybrid-agent-test" --yes --no-wait
```

## Related Templates

- [15-private-network-standard-agent-setup](../15-private-network-standard-agent-setup/) — Fully private setup (managed VNet)
- [16-private-network-standard-agent-apim-setup-preview](../16-private-network-standard-agent-apim-setup-preview/) — Private APIM setup (reference)
- [40-basic-agent-setup](../40-basic-agent-setup/) — Basic agent setup without private networking
- [41-standard-agent-setup](../41-standard-agent-setup/) — Standard agent setup without private networking
- [01-connections](../01-connections/) — Connection templates (APIM, ModelGateway, OpenAI, etc.)
