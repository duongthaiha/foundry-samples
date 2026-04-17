# 19-extended — Network-secured AI Foundry agent (Terraform)

This folder is the Terraform equivalent of the Bicep template
`../../infrastructure-setup-bicep/19-hybrid-private-resources-agent-setup/`.

It deploys the same **hybrid / private-networked AI Foundry Agent Service**
architecture, with full feature parity:

- Azure AI Foundry account (`Microsoft.CognitiveServices/accounts`) with
  `AIServices` kind, `networkInjections` binding the account to an agent subnet.
- AI Foundry project with `CosmosDB` / `AzureStorageAccount` / `CognitiveSearch`
  connections.
- Account-scoped capability host **(referenced as existing — the backend
  auto-creates it when `networkInjections` is configured)** and an explicitly
  created project-scoped capability host.
- Virtual Network + `agent`, `pe`, `mcp` (+ optional `apim`) subnets, or
  reuse of an existing VNet.
- Private endpoints + private DNS zones (+ VNet links) for: AI Foundry
  account (3 zones), AI Search, Storage (blob), Cosmos DB, optional Microsoft
  Fabric, optional API Management.
- All required RBAC pre-capability-host assignments + post-capability-host
  blob/cosmos container assignments.
- Optional: Application Insights, API Management (StandardV2/PremiumV2)
  with OpenAI API import + policy + project ApiManagement connection, Azure
  Bastion + Windows jumpbox, VPN Gateway, cross-region Azure OpenAI
  (APIM-fronted), marketing-pipeline workflow deployment script, Teams
  publishing infrastructure (App Gateway WAF v2 + Bot Service + Teams channel).

> The original Terraform folder
> `../19-hybrid-private-resources-agent-setup/` is a simplified placeholder
> and is left untouched.

## Structure

```
19-extended/
├── README.md                           (this file)
└── code/
    ├── versions.tf                     provider pins
    ├── providers.tf                    azurerm + azapi configuration
    ├── variables.tf                    all tunable parameters
    ├── locals.tf                       naming, CIDR math, ID parsing
    ├── outputs.tf                      outputs
    ├── example.tfvars                  minimal sample values
    ├── main.tf                         resource group
    │
    ├── network-agent-vnet.tf           VNet + subnets (new or existing)
    ├── ai-account-identity.tf          Foundry account + model deployment
    ├── ai-project-identity.tf          Project + CosmosDB/Storage/Search connections
    ├── add-project-capability-host.tf  Project capability host
    ├── standard-dependent-resources.tf Storage / Cosmos / Search (new or existing)
    ├── private-endpoint-and-dns.tf     PEs + Private DNS zones + VNet links
    ├── role-assignments.tf             All RBAC (pre + post cap-host)
    │
    ├── application-insights.tf         Optional: LAW + App Insights + project connection
    ├── api-management.tf               Optional: APIM
    ├── apim-gateway-connection.tf      Optional: OpenAI API import + ApiManagement connection
    ├── bastion-jumpbox.tf               Optional: Bastion + Windows jumpbox + NAT GW
    ├── vpn-gateway.tf                   Optional: VPN Gateway
    ├── cross-region-openai-connection.tf Optional: cross-region OpenAI + APIM + PE + project connection
    ├── workflow-deployment.tf          Optional: marketing-pipeline workflow (deploymentScript)
    ├── teams-agent-publish-script.tf   Optional: Agent Application + deployment (deploymentScript)
    └── teams-publishing-infra.tf       Optional: App Gateway WAF + Bot Service + Teams channel
```

## Prerequisites

- Terraform ≥ 1.5
- Azure CLI (for `az login`)
- Providers (pinned in `versions.tf`):
  - `azurerm` ~> 4.37
  - `azapi` ~> 2.5
  - `random` ~> 3.7
  - `time` ~> 0.12
- Sufficient permissions to assign RBAC roles (Owner or User Access
  Administrator on the target resource group).

## Usage

```powershell
cd infrastructure/infrastructure-setup-terraform/19-extended/code

terraform init
terraform plan  -var-file=example.tfvars -out=plan.out
terraform apply plan.out
```

Override any variable in a `terraform.tfvars` file, e.g.:

```hcl
location              = "eastus2"
ai_services           = "contoso"
deploy_api_management = true
deploy_application_insights = true
```

### Enabling optional features

| Feature | Flag | Required inputs |
|---|---|---|
| Application Insights | `deploy_application_insights = true` | – |
| API Management | `deploy_api_management = true` | `publisher_email`, `publisher_name` |
| Bastion + jumpbox | `deploy_bastion = true` | `vm_admin_password` |
| VPN Gateway | `deploy_vpn_gateway = true` | – |
| Cross-region OpenAI | `deploy_cross_region_openai = true` | `cross_region_location`, APIM enabled |
| Workflow deployment | `deploy_workflow = true` | APIM + Foundry agents reachable |
| Teams publishing | `deploy_teams_publishing = true` | `teams_custom_domain`, APIM enabled |

### Bringing your own dependent resources

Pass ARM resource IDs to reuse existing resources instead of creating new
ones:

```hcl
existing_vnet_resource_id          = "/subscriptions/.../virtualNetworks/my-vnet"
ai_search_resource_id              = "/subscriptions/.../searchServices/my-search"
azure_storage_account_resource_id  = "/subscriptions/.../storageAccounts/mystorage"
azure_cosmosdb_account_resource_id = "/subscriptions/.../databaseAccounts/mycosmos"
api_management_resource_id         = "/subscriptions/.../service/my-apim"
fabric_workspace_resource_id       = "/subscriptions/.../workspaces/<guid>"
```

Existing private DNS zones can be reused by mapping them to their hosting
resource group:

```hcl
existing_dns_zones = {
  "privatelink.openai.azure.com"          = "hub-dns-rg"
  "privatelink.cognitiveservices.azure.com" = "hub-dns-rg"
  "privatelink.services.ai.azure.com"     = "hub-dns-rg"
  # ...
}
```

## Notes on the Bicep → Terraform port

- Bicep uses `utcNow()` for the unique suffix, which produces duplicate
  resources on redeploys. Terraform uses a `random_string` so the suffix is
  stable across applies (stored in state).
- The account-level capability host is **not** explicitly created; it is
  auto-created by the Foundry backend when `networkInjections` is set.
- The 12 small single-role-assignment Bicep modules are consolidated into
  a single `role-assignments.tf` file (grouped by target resource) for
  readability.
- Deployment scripts (workflow + teams publishing) are preserved as
  `azapi_resource` of `Microsoft.Resources/deploymentScripts@2023-08-01`
  with their original PowerShell content.
- Cross-region OpenAI is fronted by APIM with managed-identity auth
  because Azure enforces `disableLocalAuth=true` on new OpenAI resources.
