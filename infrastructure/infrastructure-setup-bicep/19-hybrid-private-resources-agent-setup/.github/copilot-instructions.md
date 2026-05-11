# Copilot Instructions — Template 19: Hybrid Private Resources Agent Setup

These instructions apply to all work inside
`infrastructure/infrastructure-setup-bicep/19-hybrid-private-resources-agent-setup/`.

## Deploy to Azure
The tenant you should use to deploy to Azure is a47f5c1a-2b77-4a4e-8c35-f0d22296c0cc
Subscription is 6372dff5-b3ec-4613-bd5d-26767f57b729
If you need login credentials, please pause and ask user

## What this template is

A Bicep deployment for an **Azure AI Foundry** account where:

- The Foundry/AI Services account has `publicNetworkAccess: Disabled` by default.
- Backend resources (AI Search, Cosmos DB, Storage) sit behind **private endpoints** in a private VNet.
- The account's `networkInjections` route Data Proxy / Agent ToolServer traffic into that VNet so agents can reach AI Search and MCP servers privately.
- Optional features: APIM AI Gateway, cross-region Azure OpenAI, Application Insights, Azure Bastion + jump box, VPN Gateway, Teams publishing, workflow agents.

`main.bicep` is the entry point. Reusable modules live in `modules-network-secured/`.
Tests live in `tests/`. GitHub Actions workflow at repo root: `.github/workflows/deploy-template-19.yml`.

## Authoring rules

### Bicep style
- Match the existing style in `main.bicep` and `modules-network-secured/`: `@description` on every parameter, `param`/`var`/`resource`/`module`/`output` ordering, camelCase names.
- Keep `uniqueSuffix` derived from `uniqueString(resourceGroup().id)` — it must stay stable across redeployments. Do **not** reintroduce `utcNow()`-based suffixes; that caused duplicate-resource bugs on redeploy.
- New optional features must be **off by default** behind a `deploy<Feature>` bool param so basic deploys stay cheap and fast.
- When a resource may be brought-your-own, accept a `<resource>ResourceId` string param (empty default) and branch with `existing` references in a dedicated module, mirroring `aiSearchResourceId` / `azureCosmosDBAccountResourceId` / `azureStorageAccountResourceId` / `apiManagementResourceId`.
- Don't hard-code regions, subscription IDs, tenant IDs, or resource names. Derive names from params + `uniqueSuffix`.
- Keep generated ARM JSON (`main.json`, `add-project.json`, `cross-region-openai-connection.json`, `vpn-gateway.json`, etc.) in sync when you change the matching `.bicep`. Regenerate with `az bicep build`.

### Capability host
- The account-level capability host is **auto-created by the backend** when `networkInjections` are configured. In Bicep, reference it with `existing` (see `modules-network-secured/add-project-capability-host.bicep`). Never `resource ... = { ... }` create it — that produces `Conflict` errors.

### Networking invariants
- Foundry account stays `publicNetworkAccess: Disabled` by default. If you add a code path that enables public access, gate it behind an explicit param and call it out in the README's "Switching Between Private and Public Access" section.
- Private endpoints + private DNS zones for AI Search, Cosmos DB, Storage, APIM, OpenAI, Fabric all flow through `modules-network-secured/private-endpoint-and-dns.bicep`. Add new PE/DNS pairs there rather than scattering them.
- Subnets are defined in `network-agent-vnet.bicep`. Respect the agent/PE/MCP/APIM/Bastion/Gateway subnet split; APIM StandardV2/PremiumV2 are the only SKUs that support PE.
- When adding a new service that needs VNet egress from agents, route it through the Data Proxy via `networkInjections` rather than opening the account publicly.

### Data-plane vs control-plane
- ARM control-plane (`Microsoft.Resources/deployments`, role assignments, PE creation) always works from public runners.
- Data-plane steps (Foundry Agent Application creation, workflow agent deployment, Teams publishing, Foundry IQ knowledge sources) hit private FQDNs and **only resolve inside the VNet**. Any new `deploymentScripts` that call Foundry data-plane APIs must either:
  1. be gated behind a feature flag and documented as "requires self-hosted runner / jump box", or
  2. use `containerSettings.subnetIds` to run on a delegated subnet (see option E in README).
- The GitHub workflow's preflight job already fails fast when `runner=github-hosted` is combined with `deployWorkflow` or `deployTeamsPublishing`. Keep that guard in sync when you add new data-plane toggles.

### Role assignments
- Reuse the dedicated role-assignment modules (`ai-account-to-search-role-assignment.bicep`, `cosmosdb-account-role-assignment.bicep`, `blob-storage-container-role-assignments.bicep`, etc.). Don't inline `Microsoft.Authorization/roleAssignments` in feature modules.
- Use least-privilege built-in roles. If you need a new role, add it as a `var` with a comment naming the role.

## Testing & validation

- Lint Bicep before committing: `az bicep build --file main.bicep` (and any module you changed).
- For PR review, `mode: whatif` on the workflow shows the resource diff without provisioning.
- Python SDK tests in `tests/` (`test_agents_v2.py`, `test_apim_gateway_agents_v2.py`, `test_ai_search_tool_agents_v2.py`, `test_mcp_tools_agents_v2.py`) require `PROJECT_ENDPOINT` env var and **must be run from inside the VNet** (Bastion jump box, VPN, or self-hosted runner) when the account is private.
- After changing a `.bicep`, regenerate the matching `.json` and include both in the commit.

## Docs to keep in sync

When you add a feature flag, new module, or change deploy semantics, update:
- `README.md` (Modules table, Deployment examples, Key Features table)
- `PUBLISH.md` / `PrivateDeploy.md` if the change affects the publish/private-deploy flow
- `diagrams/architecture.md` and `diagrams/sequence-diagram.md` if topology changes
- `metadata.json` for template metadata
- The repo-root workflow `.github/workflows/deploy-template-19.yml` if you add a toggle a user should be able to set from `workflow_dispatch`

## Things not to do

- Do **not** commit secrets, subscription IDs, tenant IDs, or jump-box passwords. `jumpboxAdminPassword` is a `@secure()` param — keep it that way.
- Do **not** flip the Foundry account to `publicNetworkAccess: Enabled` as a default to "make tests pass". Fix the private-network path instead.
- Do **not** add `utcNow()` to anything that contributes to a resource name or suffix.
- Do **not** create the capability host directly; reference the auto-created one with `existing`.
- Do **not** introduce data-plane `deploymentScripts` without either a self-hosted-runner gate or `containerSettings.subnetIds`.
