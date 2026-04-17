# Private Networking Deployment Guide

This guide walks through deploying the **Hybrid Private Resources Agent Setup** (Template 19) end-to-end in a fully private networking configuration. It covers infrastructure deployment, DNS configuration, local machine connectivity, and knowledge source (Foundry IQ) creation.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Step 1: Deploy the Infrastructure](#step-1-deploy-the-infrastructure)
4. [Step 2: Verify Private Endpoints and DNS](#step-2-verify-private-endpoints-and-dns)
5. [Step 3: Configure Local DNS Resolution](#step-3-configure-local-dns-resolution)
6. [Step 4: Connect to the Private Network](#step-4-connect-to-the-private-network)
7. [Step 5: Verify Connectivity](#step-5-verify-connectivity)
8. [Step 6: Create Knowledge Sources (Foundry IQ)](#step-6-create-knowledge-sources-foundry-iq)
9. [Step 7: Test Agents with Private Resources](#step-7-test-agents-with-private-resources)
10. [RBAC Reference](#rbac-reference)
11. [Network Architecture Reference](#network-architecture-reference)
12. [Troubleshooting](#troubleshooting)

---

## Overview

This template deploys all resources with **private network access only**:

| Resource | Public Access | Access Method |
|----------|---------------|---------------|
| AI Services Account | Disabled | Private endpoint |
| AI Search | Disabled | Private endpoint |
| Storage Account | Disabled | Private endpoint |
| Cosmos DB | Disabled | Private endpoint |

All communication between services uses **managed identities** over **private endpoints**. The Data Proxy (network injection) routes agent tool calls through the VNet to reach private backend resources.

```
Your Machine ──VPN/Bastion──► Private VNet
                                 │
                    ┌────────────┼────────────┐
                    │            │             │
              ┌─────▼─────┐ ┌───▼───┐ ┌──────▼──────┐
              │ AI Services│ │Search │ │   Storage   │
              │  (private) │ │(priv.)│ │  (private)  │
              └─────┬──────┘ └───┬───┘ └──────┬──────┘
                    │            │             │
              ┌─────▼────────────▼─────────────▼──┐
              │       Private DNS Zones            │
              │  (privatelink.*.azure.com)         │
              └────────────────────────────────────┘
```

---

## Prerequisites

1. **Azure CLI** installed and authenticated (`az login`)
2. **Bicep CLI** installed (`az bicep install`)
3. **Owner** role on the target subscription (required for RBAC assignments)
4. Sufficient **model quota** for the target region
5. Required **resource providers** registered:

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.Search
az provider register --namespace Microsoft.CognitiveServices
az provider register --namespace Microsoft.DocumentDB
```

---

## Step 1: Deploy the Infrastructure

### Option A: Bastion + Jump Box (Recommended for Portal Access)

This deploys a jump box VM in the VNet so you can access private resources from the Azure portal via Bastion.

```bash
RESOURCE_GROUP="rg-hybrid-agent-private"
LOCATION="eastus2"

az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file main.bicep \
  --parameters \
    location="$LOCATION" \
    deployBastion=true \
    jumpboxAdminPassword="YourSecureP@ssw0rd!"
```

### Option B: VPN Gateway (For Local Machine Connectivity)

This deploys a VPN Gateway for point-to-site or site-to-site connectivity.

```bash
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file main.bicep \
  --parameters \
    location="$LOCATION" \
    deployVpnGateway=true \
    vpnGatewaySku="VpnGw1"
```

> **Note:** VPN Gateway provisioning takes **30–45 minutes**.

### Option C: Existing VNet (Bring Your Own Network)

If you have an existing VNet with VPN/ExpressRoute already configured:

```bash
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file main.bicep \
  --parameters \
    location="$LOCATION" \
    existingVnetResourceId="/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet-name}" \
    agentSubnetPrefix="10.0.0.0/24" \
    peSubnetPrefix="10.0.1.0/24"
```

> **Important:** Ensure subnet prefixes don't overlap with existing subnets. Avoid reserved ranges: `169.254.0.0/16`, `172.30.0.0/16`, `172.31.0.0/16`.

### Option D: Full Deploy (All Features)

```bash
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file main.bicep \
  --parameters \
    location="$LOCATION" \
    deployApiManagement=true \
    publisherEmail="admin@yourorg.com" \
    publisherName="YourOrg" \
    deployBastion=true \
    jumpboxAdminPassword="YourSecureP@ssw0rd!" \
    deployApplicationInsights=true
```

### Verify Deployment

```bash
az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name "main" \
  --query "properties.provisioningState" -o tsv
```

Expected output: `Succeeded`

---

## Step 2: Verify Private Endpoints and DNS

### List Private Endpoints

```bash
az network private-endpoint list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[].{Name:name, PrivateIP:customDnsConfigurations[0].ipAddresses[0], Status:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" \
  -o table
```

Expected output (4+ endpoints):

```
Name                                    PrivateIP      Status
--------------------------------------  -------------- --------
aiservicesXXXX-private-endpoint         192.168.1.4    Approved
aiservicesXXXXsearch-private-endpoint   192.168.1.10   Approved
aiservicesXXXXstorage-private-endpoint  192.168.1.9    Approved
aiservicesXXXXcosmosdb-private-endpoint 192.168.1.7    Approved
```

### List Private DNS Zones

```bash
az network private-dns zone list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[].{Zone:name, Records:numberOfRecordSets}" \
  -o table
```

Expected zones:

| Zone | Purpose |
|------|---------|
| `privatelink.services.ai.azure.com` | AI Services |
| `privatelink.openai.azure.com` | OpenAI endpoints |
| `privatelink.cognitiveservices.azure.com` | Cognitive Services |
| `privatelink.search.windows.net` | AI Search |
| `privatelink.blob.core.windows.net` | Blob Storage |
| `privatelink.documents.azure.com` | Cosmos DB |

### Get Private Endpoint IP Addresses

```bash
# Get all private endpoint IPs for hosts file configuration
az network private-endpoint list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[].{Name:name, FQDN:customDnsConfigurations[0].fqdn, IP:customDnsConfigurations[0].ipAddresses[0]}" \
  -o table
```

---

## Step 3: Configure Local DNS Resolution

When connecting via VPN or with direct network access, your machine needs to resolve private endpoint FQDNs to their private IP addresses.

### Option A: Hosts File (Quick Setup)

Add entries to your machine's hosts file. Run the following script to generate them automatically:

**PowerShell:**

```powershell
$RG = "rg-hybrid-agent-private"

# Get all private endpoints and their DNS configs
$endpoints = az network private-endpoint list --resource-group $RG -o json | ConvertFrom-Json

foreach ($ep in $endpoints) {
    foreach ($dns in $ep.customDnsConfigurations) {
        $ip = $dns.ipAddresses[0]
        $fqdn = $dns.fqdn
        Write-Host "$ip $fqdn"
    }
}
```

Then add the output to your hosts file:
- **Windows:** `C:\Windows\System32\drivers\etc\hosts` (run as Administrator)
- **Linux/macOS:** `/etc/hosts` (run with `sudo`)

Example entries:

```
# Azure AI Foundry Private Endpoints
192.168.1.4  aiservicesXXXX.cognitiveservices.azure.com
192.168.1.4  aiservicesXXXX.openai.azure.com
192.168.1.4  aiservicesXXXX.services.ai.azure.com
192.168.1.7  aiservicesXXXXcosmosdb.documents.azure.com
192.168.1.8  aiservicesXXXXcosmosdb-eastus2.documents.azure.com
192.168.1.9  aiservicesXXXXstorage.blob.core.windows.net
192.168.1.10 aiservicesXXXXsearch.search.windows.net
```

### Option B: Azure Private DNS Resolver (Production)

For production, configure an [Azure Private DNS Resolver](https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-overview) or a conditional forwarder on your on-premises DNS server to resolve `*.privatelink.*` zones to the Azure Private DNS zones.

### Option C: VPN with Azure DNS (Automatic)

If you use Azure VPN Gateway with point-to-site configuration, configure the VPN client to use Azure DNS (`168.63.129.16`) for automatic private DNS resolution.

---

## Step 4: Connect to the Private Network

### Via Azure Bastion (Portal Access)

1. Navigate to **Azure Portal** → **Virtual Machines** → `XXXX-jumpbox`
2. Click **Connect** → **Bastion**
3. Enter username: `azureuser` and the password you provided during deployment
4. From the jump box, access [ai.azure.com](https://ai.azure.com) or run CLI/SDK commands

### Via VPN Gateway

1. Download the VPN client configuration:
   ```bash
   az network vnet-gateway vpn-client generate \
     --resource-group "$RESOURCE_GROUP" \
     --name "<gateway-name>" \
     --authentication-method EAPTLS \
     -o tsv
   ```
2. Install the VPN client profile
3. Connect to the VPN
4. Configure DNS (see [Step 3](#step-3-configure-local-dns-resolution))

### Via ExpressRoute

If you have an existing ExpressRoute circuit, peer it with the VNet and configure DNS forwarding to Azure Private DNS zones.

---

## Step 5: Verify Connectivity

After connecting to the VNet (or from the jump box), verify that you can reach all private endpoints:

```bash
# Verify DNS resolution (should return private IPs, not public)
nslookup aiservicesXXXXsearch.search.windows.net
# Expected: 192.168.1.10 (private IP)

nslookup aiservicesXXXXstorage.blob.core.windows.net
# Expected: 192.168.1.9 (private IP)

nslookup aiservicesXXXX.services.ai.azure.com
# Expected: 192.168.1.4 (private IP)
```

```bash
# Test connectivity to AI Search
curl -s -o /dev/null -w "%{http_code}" \
  "https://aiservicesXXXXsearch.search.windows.net/servicestats?api-version=2024-07-01" \
  -H "Authorization: Bearer $(az account get-access-token --resource https://search.azure.com --query accessToken -o tsv)"
# Expected: 200
```

```powershell
# PowerShell: Test TCP connectivity to all private endpoints
@(
    "aiservicesXXXX.services.ai.azure.com",
    "aiservicesXXXXsearch.search.windows.net",
    "aiservicesXXXXstorage.blob.core.windows.net",
    "aiservicesXXXXcosmosdb.documents.azure.com"
) | ForEach-Object {
    $result = Test-NetConnection -ComputerName $_ -Port 443 -WarningAction SilentlyContinue
    Write-Host "$_ : $($result.TcpTestSucceeded)"
}
```

---

## Step 6: Create Knowledge Sources (Foundry IQ)

Knowledge sources allow agents to search over your data using AI Search. In a private deployment, special RBAC and networking configuration is required.

### What the Template Configures Automatically

The Bicep template sets up all required cross-service RBAC for knowledge sources:

| Source Identity | Target Resource | Role | Purpose |
|----------------|-----------------|------|---------|
| AI Search MI | Storage Account | Storage Blob Data Reader | Index blobs for knowledge sources |
| AI Search MI | AI Services | Cognitive Services OpenAI User | Use embedding models during indexing |
| AI Account MI | AI Search | Search Index Data Contributor | Manage search indexes |
| AI Account MI | AI Search | Search Service Contributor | Manage search service |
| AI Account MI | Storage Account | Storage Blob Data Contributor | Read/write blob data |
| Project MI | AI Search | Search Index Data Contributor | Query search indexes |
| Project MI | AI Search | Search Service Contributor | Manage search service |
| Project MI | Storage | Storage Blob Data Contributor | Access blob storage |
| Project MI | Cosmos DB | Cosmos DB Operator | Manage Cosmos DB |

The AI Search service also has `networkRuleSet.bypass: 'AzureServices'` to allow trusted Azure service access.

### Creating a Knowledge Source via the Portal

1. Ensure you're connected to the private VNet (VPN/Bastion/ExpressRoute)
2. Navigate to [ai.azure.com](https://ai.azure.com) → your project
3. Go to **Knowledge** → **+ Create knowledge source**
4. Select **Azure Blob Storage** as the source
5. Configure the embedding model (e.g., `text-embedding-3-small`) and chat model (e.g., `gpt-4o`)
6. Select the storage container with your documents
7. Click **Create**

> **Note on portal access:** The Foundry portal makes API calls directly from your browser to the search service endpoint. If you get a 401 error, see [Troubleshooting: Portal 401 on Knowledge Source Creation](#portal-401-on-knowledge-source-creation).

### Creating a Knowledge Source via CLI

From a machine connected to the VNet (or the jump box):

```bash
# Get a token for the search service
TOKEN=$(az account get-access-token --resource "https://search.azure.com" --query accessToken -o tsv)

SEARCH_NAME="aiservicesXXXXsearch"
STORAGE_RESOURCE_ID="/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/aiservicesXXXXstorage"
OPENAI_ENDPOINT="https://aiservicesXXXX.openai.azure.com/"

curl -X PUT \
  "https://${SEARCH_NAME}.search.windows.net/knowledgesources/my-knowledge-source?api-version=2025-11-01-Preview" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-knowledge-source",
    "kind": "azureBlob",
    "azureBlobParameters": {
      "ingestionParameters": {
        "contentExtractionMode": "minimal",
        "embeddingModel": {
          "kind": "azureOpenAI",
          "azureOpenAIParameters": {
            "resourceUri": "'"$OPENAI_ENDPOINT"'",
            "deploymentId": "text-embedding-3-small",
            "modelName": "text-embedding-3-small"
          }
        },
        "chatCompletionModel": {
          "kind": "azureOpenAI",
          "azureOpenAIParameters": {
            "resourceUri": "'"$OPENAI_ENDPOINT"'",
            "deploymentId": "gpt-4o",
            "modelName": "gpt-4o"
          }
        },
        "disableImageVerbalization": false
      },
      "containerName": "your-container-name",
      "connectionString": "ResourceId='"$STORAGE_RESOURCE_ID"'/;"
    }
  }'
```

Expected response: `HTTP 201 Created`

### Verifying Knowledge Source Status

```bash
# List all knowledge sources
curl -s \
  "https://${SEARCH_NAME}.search.windows.net/knowledgesources?api-version=2025-11-01-Preview" \
  -H "Authorization: Bearer $TOKEN" | python -m json.tool

# Check indexer status (created automatically by the knowledge source)
curl -s \
  "https://${SEARCH_NAME}.search.windows.net/indexers/my-knowledge-source-indexer/status?api-version=2024-07-01" \
  -H "Authorization: Bearer $TOKEN" | python -m json.tool
```

---

## Step 7: Test Agents with Private Resources

### Set Up Test Environment

```bash
# From the jump box or a VPN-connected machine
export PROJECT_ENDPOINT="https://aiservicesXXXX.services.ai.azure.com/api/projects/projectXXXX"

pip install azure-ai-projects azure-identity
```

### Test Basic Agent

```bash
python tests/test_agents_v2.py
```

### Test Agent with AI Search Tool

```bash
export AI_SEARCH_CONNECTION_NAME="aiservicesXXXXsearch"
python tests/test_ai_search_tool_agents_v2.py
```

### Test Agent with Knowledge Source

```python
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    AzureAISearchAgentTool,
    AzureAISearchToolResource,
    AISearchIndexResource,
    PromptAgentDefinition,
)
from azure.identity import DefaultAzureCredential

client = AIProjectClient(
    endpoint="https://aiservicesXXXX.services.ai.azure.com/api/projects/projectXXXX",
    credential=DefaultAzureCredential(),
)

# Use the index created by the knowledge source
agent = client.agents.create_version(
    agent_name="knowledge-agent",
    definition=PromptAgentDefinition(
        model="gpt-4o-mini",
        instructions="You answer questions using the knowledge base.",
        tools=[
            AzureAISearchAgentTool(
                resource=AzureAISearchToolResource(
                    searches=[
                        AISearchIndexResource(
                            index_name="my-knowledge-source-index",
                            index_connection_id="aiservicesXXXXsearch",
                        )
                    ]
                )
            )
        ],
    ),
)
```

For the full test suite, see [tests/TESTING-GUIDE.md](tests/TESTING-GUIDE.md).

---

## RBAC Reference

### Service Managed Identities

The template creates **three managed identities** that work together:

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   AI Account MI  │     │   Project MI     │     │  AI Search MI    │
│                  │     │                  │     │                  │
│ Roles on:        │     │ Roles on:        │     │ Roles on:        │
│ • Search (2)     │     │ • Search (2)     │     │ • Storage (1)    │
│ • Storage (1)    │     │ • Storage (2)    │     │ • AI Services (1)│
│                  │     │ • Cosmos DB (2)  │     │                  │
└──────────────────┘     └──────────────────┘     └──────────────────┘
```

### Complete Role Assignment Matrix

| # | Principal | Target | Role | Role Definition ID | Purpose |
|---|-----------|--------|------|--------------------|---------|
| 1 | Project MI | AI Search | Search Index Data Contributor | `8ebe5a00-799e-43f5-93ac-243d3dce84a7` | Query/write search indexes |
| 2 | Project MI | AI Search | Search Service Contributor | `7ca78c08-252a-4471-8644-bb5ff32d4ba0` | Manage search service |
| 3 | Project MI | Storage | Storage Blob Data Contributor | `ba92f5b4-2d11-453d-a403-e96b0029c9fe` | Read/write blobs |
| 4 | Project MI | Storage | Storage Blob Data Owner (conditional) | `b7e6dc6d-f1e8-4753-8033-0f276bb0955b` | Agent-scoped blob access |
| 5 | Project MI | Cosmos DB | Cosmos DB Operator | `230815da-be43-4aae-9cb4-875f7bd000aa` | Manage Cosmos DB |
| 6 | Project MI | Cosmos DB | Built-In Data Contributor | `00000000-0000-0000-0000-000000000002` | Read/write Cosmos data |
| 7 | AI Search MI | Storage | Storage Blob Data Reader | `acdd72a7-3385-48ef-bd42-f606fba81ae7` | Index blobs for knowledge sources |
| 8 | AI Search MI | AI Services | Cognitive Services OpenAI User | `5e0bd9bd-7b93-4f28-af87-19fc36ad61bd` | Use embedding/chat models |
| 9 | AI Account MI | AI Search | Search Index Data Contributor | `8ebe5a00-799e-43f5-93ac-243d3dce84a7` | Manage search indexes |
| 10 | AI Account MI | AI Search | Search Service Contributor | `7ca78c08-252a-4471-8644-bb5ff32d4ba0` | Manage search service |
| 11 | AI Account MI | Storage | Storage Blob Data Contributor | `ba92f5b4-2d11-453d-a403-e96b0029c9fe` | Read/write blobs |

### User RBAC for Portal Access

If you need to use the Foundry portal to create knowledge sources, your user also needs roles on the search service:

```bash
# Get your search service resource ID
SEARCH_ID=$(az search service show \
  --name "aiservicesXXXXsearch" \
  --resource-group "$RESOURCE_GROUP" \
  --query id -o tsv)

# Assign data-plane access
az role assignment create \
  --role "Search Index Data Contributor" \
  --assignee "your-user@yourdomain.com" \
  --scope "$SEARCH_ID"

az role assignment create \
  --role "Search Service Contributor" \
  --assignee "your-user@yourdomain.com" \
  --scope "$SEARCH_ID"
```

---

## Network Architecture Reference

### Subnets

| Subnet | Default CIDR | Purpose | Delegation |
|--------|-------------|---------|------------|
| `agent-subnet` | `192.168.0.0/24` | AI Foundry Data Proxy (network injection) | `Microsoft.App/environments` |
| `pe-subnet` | `192.168.1.0/24` | Private endpoints for all services | None |
| `mcp-subnet` | `192.168.2.0/24` | MCP server Container Apps | `Microsoft.App/environments` |
| `apim-subnet` | `192.168.3.0/24` | APIM outbound VNet integration | `Microsoft.Web/serverFarms` |
| `AzureBastionSubnet` | `192.168.4.0/26` | Azure Bastion (if deployed) | None |
| `jumpbox-subnet` | `192.168.6.0/24` | Jump box VM (if deployed) | None |
| `GatewaySubnet` | `192.168.255.0/27` | VPN Gateway (if deployed) | None |

### Private DNS Zones

| DNS Zone | Service | Records |
|----------|---------|---------|
| `privatelink.services.ai.azure.com` | AI Services | A record → PE IP |
| `privatelink.openai.azure.com` | OpenAI endpoints | A record → PE IP |
| `privatelink.cognitiveservices.azure.com` | Cognitive Services | A record → PE IP |
| `privatelink.search.windows.net` | AI Search | A record → PE IP |
| `privatelink.blob.core.windows.net` | Blob Storage | A record → PE IP |
| `privatelink.documents.azure.com` | Cosmos DB | A record → PE IP |

### Service Network Configuration

| Service | Public Access | Bypass | Auth Mode |
|---------|---------------|--------|-----------|
| AI Services | Disabled | AzureServices | AAD + Local |
| AI Search | Disabled | AzureServices | AAD or API Key (401 challenge) |
| Storage | Disabled | AzureServices | AAD only (no shared keys) |
| Cosmos DB | Disabled | None | AAD only (no local auth) |

---

## Troubleshooting

### DNS Resolves to Public IP Instead of Private

**Symptom:** `nslookup` or `Resolve-DnsName` returns a public IP instead of a private IP (192.168.x.x).

**Cause:** Your machine is not using the Azure Private DNS zones for resolution.

**Fix:**
- If using VPN, configure the VPN client to use Azure DNS (`168.63.129.16`)
- Add entries to your hosts file (see [Step 3](#step-3-configure-local-dns-resolution))
- If using a custom DNS server, configure conditional forwarders for `privatelink.*` zones

### Portal 401 on Knowledge Source Creation

**Symptom:** Creating a knowledge source from [ai.azure.com](https://ai.azure.com) returns `401 Unauthorized`.

**Cause:** The portal makes API calls **directly from your browser** to the search service. This requires:
1. Your browser can reach the search service private endpoint (network connectivity)
2. Your user has the correct data-plane RBAC roles on the search service
3. The search service's managed identity has access to the storage account

**Fix:**

```bash
# 1. Assign user RBAC on search service
SEARCH_ID=$(az search service show --name "aiservicesXXXXsearch" -g "$RESOURCE_GROUP" --query id -o tsv)
az role assignment create --role "Search Index Data Contributor" --assignee "you@yourdomain.com" --scope "$SEARCH_ID"
az role assignment create --role "Search Service Contributor" --assignee "you@yourdomain.com" --scope "$SEARCH_ID"

# 2. Verify search MI has Storage Blob Data Reader on storage
SEARCH_MI=$(az search service show --name "aiservicesXXXXsearch" -g "$RESOURCE_GROUP" --query identity.principalId -o tsv)
STORAGE_ID=$(az storage account show --name "aiservicesXXXXstorage" -g "$RESOURCE_GROUP" --query id -o tsv)
az role assignment list --scope "$STORAGE_ID" --assignee "$SEARCH_MI" --query "[].roleDefinitionName" -o table
# Should show "Storage Blob Data Reader"

# 3. If missing, assign it
az role assignment create --role "Storage Blob Data Reader" --assignee-object-id "$SEARCH_MI" --assignee-principal-type ServicePrincipal --scope "$STORAGE_ID"
```

> **Note:** RBAC propagation can take up to **10 minutes**. Wait and retry.

### Knowledge Source Creation Fails with Storage Credential Error

**Symptom:** `403 Forbidden` with message: *"Error with data source: Credentials provided in the connection string are invalid or have expired"*

**Cause:** The AI Search service's managed identity doesn't have access to the storage account.

**Fix:**

```bash
# Assign Storage Blob Data Reader to search MI
SEARCH_MI=$(az search service show --name "aiservicesXXXXsearch" -g "$RESOURCE_GROUP" --query identity.principalId -o tsv)
STORAGE_ID=$(az storage account show --name "aiservicesXXXXstorage" -g "$RESOURCE_GROUP" --query id -o tsv)

az role assignment create \
  --role "Storage Blob Data Reader" \
  --assignee-object-id "$SEARCH_MI" \
  --assignee-principal-type ServicePrincipal \
  --scope "$STORAGE_ID"

# Also add a resource access rule for network-level access
az storage account network-rule add \
  --account-name "aiservicesXXXXstorage" \
  --resource-group "$RESOURCE_GROUP" \
  --resource-id "$(az search service show --name aiservicesXXXXsearch -g $RESOURCE_GROUP --query id -o tsv)" \
  --tenant-id "$(az account show --query tenantId -o tsv)"
```

### Knowledge Source Indexing Fails with OpenAI Auth Error

**Symptom:** Indexer status shows errors about authentication to the OpenAI endpoint.

**Cause:** The AI Search service's managed identity doesn't have `Cognitive Services OpenAI User` role on the AI Services account.

**Fix:**

```bash
SEARCH_MI=$(az search service show --name "aiservicesXXXXsearch" -g "$RESOURCE_GROUP" --query identity.principalId -o tsv)
AI_ACCOUNT_ID=$(az cognitiveservices account show --name "aiservicesXXXX" -g "$RESOURCE_GROUP" --query id -o tsv)

az role assignment create \
  --role "Cognitive Services OpenAI User" \
  --assignee-object-id "$SEARCH_MI" \
  --assignee-principal-type ServicePrincipal \
  --scope "$AI_ACCOUNT_ID"
```

### TaskCanceledException with MCP Tools

**Symptom:** MCP tool calls intermittently fail with `TaskCanceledException`.

**Cause:** Known issue with Data Proxy deployment across scale units. The load balancer routes requests in round-robin, and ~50% of requests may hit the wrong scale unit.

**Workaround:** Retry the request. Use `--retry 3` in test scripts.

### Portal Shows "New Foundry Not Supported"

**Symptom:** The Foundry portal displays a message that the new Foundry experience is not supported.

**Cause:** Expected when network injection is configured. The portal backend cannot fully interact with network-injected environments.

**Workaround:** Use SDK testing instead. All agent features work via the SDK.

---

## Related Resources

- [README.md](README.md) — Main template documentation
- [PUBLISH.md](PUBLISH.md) — Publishing agents to Microsoft Teams
- [tests/TESTING-GUIDE.md](tests/TESTING-GUIDE.md) — Comprehensive testing guide
- [Azure Private Link docs](https://learn.microsoft.com/en-us/azure/private-link/)
- [Azure AI Search private endpoints](https://learn.microsoft.com/en-us/azure/search/search-security-network-access)
- [Securely connect to Azure AI Foundry](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/configure-private-link)
