# Publish a Foundry Agent to Microsoft 365 / Teams (Private Networking)

This guide covers publishing a Foundry agent to Microsoft Teams and Microsoft 365 Copilot **when the Foundry account is on a private network** (i.e. `publicNetworkAccess=Disabled` or `networkAcls.defaultAction=Deny`).

If your Foundry account is publicly accessible, use the simpler portal flow at https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/publish-copilot instead — the steps below add infrastructure you don't need.

> **Different track — container-hosted agents:** the M365 Agent / Agent Blueprint pattern (Docker-packaged custom agent running inside a Foundry-managed runtime) is a separate sample at https://github.com/microsoft-foundry/foundry-samples/tree/main/samples/csharp/FoundryA365. That track is Frontier-preview, North Central US only, and is out of scope for this template.

## Architecture

```
Teams / M365 user
    │ HTTPS (Bot Channel protocol)
    ▼
Microsoft Bot Channel Adapters (public)
    │
    ▼
Azure Bot Service (Teams Channel enabled, msaAppId = Foundry Agent App client id)
    │ messaging endpoint = https://<customDomain>/bot
    ▼
Application Gateway WAF v2 (public IP, TLS termination via Key Vault cert)
    │
    ▼
Azure API Management (private endpoint, JWT validation of Bot Framework tokens)
    │ rewrite-uri appends ?api-version=2025-11-15-preview
    ▼
Foundry Agent Application Activity Protocol URL (private endpoint, services.ai.azure.com)
    │
    ▼
Foundry Agent (private — workflow or prompt agent in your project)
```

**Security controls in this design:**
- Foundry account stays private — never reachable from the public internet.
- WAF v2 at the edge with OWASP 3.2 in Prevention mode.
- JWT validation at APIM: issuer must be `api.botframework.com`, audience must be the specific Bot Client ID.
- TLS terminated at the App Gateway using a cert in Key Vault.
- Optional: restrict App Gateway frontend source IPs to the `AzureBotService` service tag.

See [diagrams/sequence-diagram.md](diagrams/sequence-diagram.md) for the full sequence diagram.

---

## What this template provisions vs. what you do by hand

`azd provision` with `DEPLOY_TEAMS_PUBLISHING=true` creates every ARM resource above. **But** because the Foundry data plane is private, two pre-provision manual steps are required, plus three post-provision manual steps (Foundry portal publish + M365 admin approval are interactive and not scriptable).

Manual steps in this guide are labelled **`MANUAL STEP N`** so they're easy to spot.

---

## Phase 1 — Prerequisites

### What you need before starting
- This template already provisioned with at least: VNet, Foundry account (private), AI project, APIM (`deployApiManagement=true`), Key Vault (auto-created by `teams-publishing-infra.bicep`), and a working agent in the project (e.g. `marketing-pipeline`).
- A **jumpbox VM** inside the VNet (the template provisions one when `deployBastion=true`).
- The jumpbox VM's **system-assigned managed identity** must hold these roles:
  - `Azure AI User` on the project scope
  - `Cognitive Services Contributor` on the Foundry account scope
  - `Contributor` on the resource group (used to PUT the Agent Application + Deployment)
- The Foundry agent you want to publish is created and tested.

### MANUAL STEP 1 — Register the BotService resource provider (once per subscription)

```bash
az provider register --namespace Microsoft.BotService --wait
```

This is a no-op if the provider is already registered. Skip if your subscription has it.

---

## Phase 2 — Pre-provision: data plane + cert

The template ships with two `deploymentScript`-based modules that **do not work against a private Foundry account**:

1. `teams-agent-publish-script.bicep` creates the Foundry Agent Application + Activity Protocol deployment by calling Foundry data-plane APIs. Its `deploymentScript` runs on a Microsoft-managed public ACI which cannot reach the private endpoint (TLS handshake is rejected from sources outside the VNet's primary CIDR).
2. `teams-publishing-infra.bicep` runs a second `deploymentScript` to mint a self-signed cert into Key Vault. Azure auto-provisions a storage account for the script using shared-key auth — many subscriptions have an Azure Policy that blocks shared-key, so the script fails with `KeyBasedAuthenticationNotPermitted`.

Both are gated by parameters added to this template:
- `deployTeamsPublishScript` (default `true`; set to `false` for private Foundry)
- `createTeamsTlsCert` (default `false`; pre-import a cert instead)

The two pre-provision manual steps below replace what those scripts would have done.

### MANUAL STEP 2 — Create the Foundry Agent Application + Deployment from the jumpbox

Save the script below as `private-foundry-publish-app.ps1`. Replace placeholders at the top. The script uses the jumpbox's managed identity for auth — no secrets in the script.

```powershell
$ErrorActionPreference = 'Stop'
$account='<accountName>'        # e.g. aiservicesuqle
$proj='<projectName>'           # e.g. projectuqle
$sub='<subId>'
$rg='<resourceGroup>'
$agentName='<agentName>'        # e.g. marketing-pipeline
$agentVersion='1'               # the version you want published
$appName='<applicationName>'    # e.g. marketing-pipeline-app
$deployName='<deploymentName>'  # e.g. marketing-pipeline-deployment

function MsiToken { param($r); (Invoke-RestMethod `
    -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$([uri]::EscapeDataString($r))" `
    -Headers @{Metadata="true"}).access_token }

$arm = MsiToken "https://management.azure.com"
$hdr = @{Authorization="Bearer $arm"; "Content-Type"="application/json"}
$armBase = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$account/projects/$proj"

# 1) PUT Agent Application
$appBody = @{
    properties = @{
        agents = @(@{ agentName = $agentName })
        displayName = $appName
        description = "Foundry agent published to Teams"
    }
} | ConvertTo-Json -Depth 6
Invoke-RestMethod -Uri "$armBase/applications/$appName`?api-version=2026-01-15-preview" `
    -Method Put -Headers $hdr -Body $appBody | Out-Null

# 2) PUT Agent Deployment with BOTH Responses and Activity protocols
#    NOTE: the protocol enum value is "Activity", NOT "ActivityProtocol".
$deployBody = @{
    properties = @{
        displayName = "$appName Deployment"
        deploymentType = "Managed"
        protocols = @(
            @{ protocol = "Responses"; version = "1.0" }
            @{ protocol = "Activity";  version = "1.0" }
        )
        agents = @(@{ agentName = $agentName; agentVersion = $agentVersion })
    }
} | ConvertTo-Json -Depth 6
Invoke-RestMethod -Uri "$armBase/applications/$appName/agentdeployments/$deployName`?api-version=2026-01-15-preview" `
    -Method Put -Headers $hdr -Body $deployBody | Out-Null

# 3) Read back the values you'll need in Phase 3
$app = Invoke-RestMethod -Uri "$armBase/applications/$appName`?api-version=2026-01-15-preview" -Headers $hdr
Write-Output ([PSCustomObject]@{
    botClientId         = $app.properties.defaultInstanceIdentity.clientId
    tenantId            = $app.properties.defaultInstanceIdentity.tenantId
    activityProtocolUrl = "$($app.properties.baseUrl)/protocols/activityprotocol"
} | ConvertTo-Json -Compress)
```

Run it on the jumpbox via `az vm run-command`:

```bash
az vm run-command invoke \
  -g <rg> -n <jumpbox-vm> \
  --command-id RunPowerShellScript \
  --scripts "@private-foundry-publish-app.ps1" \
  --query "value[0].message" -o tsv
```

**Save the three values from the output** — you need them in Phase 3:
- `botClientId`
- `tenantId`
- `activityProtocolUrl`

> The Foundry API uses the protocol enum value **`Activity`** (not `ActivityProtocol`). The in-repo `teams-agent-publish-script.bicep` has been corrected — but if you have older copies, fix them.

### MANUAL STEP 3 — Pre-create the App Gateway public IP, choose a domain, and import the TLS cert

The App Gateway needs the cert already in Key Vault before it can start (because the listener references the Key Vault secret). The pre-created PIP also gives you a deterministic IP so you can decide the custom domain *before* `azd provision` runs.

#### 3a. Create the public IP

```bash
# Naming convention: <accountName>-appgw-pip — the module adopts an existing PIP with this name.
PIP_NAME="<accountName>-appgw-pip"

az network public-ip create \
    -g <rg> -n $PIP_NAME \
    --sku Standard --tier Regional \
    --allocation-method Static \
    --zone 1 2 3 \
    --location <region>

PIP=$(az network public-ip show -g <rg> -n $PIP_NAME --query ipAddress -o tsv)
echo "PIP: $PIP"
```

#### 3b. Choose a custom domain

**Option A — you own a DNS domain (production path):**
- Use whatever subdomain you want, e.g. `agent.contoso.com`.
- Create an `A` record at your registrar pointing the subdomain to `$PIP`.
- TTL 300 is fine.

**Option B — no domain (dev/test only):**
- Use `<PIP>.nip.io`. nip.io is a free public wildcard DNS service that resolves any `<ip>.nip.io` to `<ip>` with no signup. Example: if PIP is `4.166.211.190`, your custom domain is `4.166.211.190.nip.io`.
- ⚠ Some strict M365 tenants flag nip.io domains as low-reputation during admin approval. Fine for dev/test; replace with a real domain before going live.

```bash
CUSTOM_DOMAIN="$PIP.nip.io"   # or your real domain
```

#### 3c. Import a TLS cert into Key Vault

The Key Vault is named `<accountName>-kv` (auto-created by `teams-publishing-infra.bicep`).

**Option A — production: real domain + CA-issued cert.** Get a Let's Encrypt cert (any registrar, DNS-01 or HTTP-01) or a commercial cert for your domain. Convert to PFX. The repo provides `scripts/obtain-letsencrypt-cert.ps1` as a starting point (it uses certbot DNS-01; adapt for your registrar).

**Option B — dev/test: self-signed.** Bot Channel Adapters will reject a self-signed cert when relaying real Teams traffic. App Gateway and APIM accept it for control-plane provisioning, so you can verify everything builds — but you must swap to a real cert before Teams chats will work. See [Cert rotation](#cert-rotation) below.

```powershell
# Generate a self-signed PFX
$cert = New-SelfSignedCertificate `
    -DnsName "$env:CUSTOM_DOMAIN" `
    -CertStoreLocation Cert:\CurrentUser\My `
    -KeyExportPolicy Exportable `
    -NotAfter (Get-Date).AddYears(1)
$pwd = ConvertTo-SecureString -String "BotTls!Demo" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath bot-tls.pfx -Password $pwd
```

Then grant yourself permission to write certs to Key Vault and import:

```bash
ME=$(az ad signed-in-user show --query id -o tsv)
KV_ID="/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<accountName>-kv"

az role assignment create --assignee $ME --role "Key Vault Certificates Officer" --scope $KV_ID
# Wait ~30s for the role to propagate before importing.

az keyvault certificate import \
    --vault-name "<accountName>-kv" \
    --name teams-bot-tls \
    --file bot-tls.pfx \
    --password "BotTls!Demo"
```

The cert name **must** be exactly `teams-bot-tls` — that's what the App Gateway listener references.

---

## Phase 3 — `azd provision`

Set the env vars and provision. Expect ~10-15 minutes (App Gateway is the slow piece).

```bash
azd env set DEPLOY_TEAMS_PUBLISHING true
azd env set DEPLOY_TEAMS_PUBLISH_SCRIPT false       # bypass the broken data-plane deploymentScript
azd env set BOT_CLIENT_ID "<from Phase 2 Step 2>"
azd env set ACTIVITY_PROTOCOL_URL "<from Phase 2 Step 2>"
azd env set TEAMS_CUSTOM_DOMAIN "<from Phase 2 Step 3b>"
azd env set TEAMS_AGENT_NAME "<your agent name>"
azd env set TEAMS_APPLICATION_NAME "<your app name — same as Phase 2 Step 2>"

# Also set this (in main.parameters.json or via an additional env var if your azd setup supports it):
# createTeamsTlsCert=false   — bypass the broken cert deploymentScript; uses the cert we pre-imported.

azd provision
```

This creates:
- WAF policy + Application Gateway WAF v2 (zone-redundant PIP — the one you pre-created in Step 3a is adopted)
- APIM `bot-messaging` API + JWT validation policy + path rewrite to append `?api-version=2025-11-15-preview`
- Azure Bot Service S1 with messaging endpoint `https://<customDomain>/bot`
- Microsoft Teams Channel + WebChat + DirectLine channels on the Bot Service
- Key Vault adopted (idempotent — pre-imported cert preserved)

No manual steps in this phase.

---

## Phase 4 — Post-provision: validate, publish, approve

### MANUAL STEP 4 — Validate the stack

Quick health checks:

```bash
RG=<rg>
ACCT=<accountName>
DOMAIN=<customDomain>

# App Gateway provisioning + operational state
az network application-gateway show \
  -g $RG -n $ACCT-appgw \
  --query "{state:provisioningState, op:operationalState}" -o table

# App Gateway backend health (APIM should report Healthy)
az network application-gateway show-backend-health \
  -g $RG --name $ACCT-appgw \
  --query "backendAddressPools[0].backendHttpSettingsCollection[0].servers[0].health" -o tsv

# Bot Service messaging endpoint + msaAppId
az resource show -g $RG --resource-type Microsoft.BotService/botServices -n <applicationName>-bot \
  --query "{endpoint:properties.endpoint, appId:properties.msaAppId, state:properties.provisioningState}" -o table

# Bot channels (MsTeamsChannel should be present and isEnabled=true)
az rest --method get \
  --uri "https://management.azure.com/subscriptions/<sub>/resourceGroups/$RG/providers/Microsoft.BotService/botServices/<applicationName>-bot/channels?api-version=2022-09-15" \
  --query "value[].{name:name, enabled:properties.properties.isEnabled}" -o table

# APIM bot-messaging API
az apim api show -g $RG --service-name $ACCT-appgwapim --api-id bot-messaging \
  --query "{path:path, serviceUrl:serviceUrl}" -o table

# Public TLS reachability (replace with your domain)
curl -vk https://$DOMAIN/bot 2>&1 | grep -E "subject:|issuer:|HTTP/"
```

Expected results:
- App Gateway `provisioningState=Succeeded`, `operationalState=Running`
- Backend health `Healthy` (if `Unhealthy`, see [Troubleshooting](#troubleshooting))
- Bot Service `endpoint=https://<customDomain>/bot`, `msaAppId=<botClientId>`
- `MsTeamsChannel.isEnabled=true`
- APIM `serviceUrl` = the Activity Protocol URL from Phase 2
- `curl` returns the cert chain matching your domain

### MANUAL STEP 5 — Publish via the Foundry portal

This step is interactive — the Foundry portal does not expose a programmatic API for it. The portal hits ARM (control plane) which is reachable even though the data plane is private.

1. Open https://ai.azure.com → switch to your **Foundry account** → open your **project**.
2. Navigate to **Agents** in the left nav → select your agent (e.g. `marketing-pipeline`).
3. Click **Publish** in the top-right.
4. Click the arrow next to **Active version** and pick the version you want users to interact with (or **Always use latest**).
5. Click **Publish to Teams and Microsoft 365 Copilot**.
6. In the **Publish to Teams and Microsoft 365** dialog:
   - **Azure Bot Service** is shown as *read-only* because we pre-created it. Confirm it points at `<applicationName>-bot`.
   - **Name** — display name in the M365 agent store (e.g. `Marketing Pipeline`).
   - **Publish version** — three-part semver (e.g. `1.0.0`).
   - **Short description** — one sentence (visible in the store card).
   - **Description** — longer description.
   - **Developer** — your org name (max 32 chars).
   - (Optional) Expand **More** for developer website, terms of use, privacy statement URLs (HTTPS required).
7. Click **Next: Publish options**.
8. Under **Direct publish** → **Choose who can use this agent**, pick:
   - **Just you** — available immediately under **Your agents**; share by sending the agent link.
   - **People in your organization** — submitted for M365 admin approval (recommended for production).
9. Click **Publish**. A **Publish successful** dialog confirms submission.

> **Don't put secrets in any metadata field.** Names, descriptions and URLs are visible to users.

### MANUAL STEP 6 — M365 admin approval (organization scope only)

Required only if you selected **People in your organization** in Step 5.

1. A user with the **Microsoft 365 admin** role signs in to https://admin.cloud.microsoft/#/agents/all/requested.
2. The agent appears under **Requests**.
3. Admin reviews metadata and clicks **Approve**.
4. After approval, the agent appears under **Built by your org** in the M365 Copilot agent store and in Teams for all tenant users (subject to app policies).

You can return to the same URL any time to check approval status.

---

## Cert rotation

After Phase 3 succeeds you can swap the TLS cert in Key Vault at any time without re-provisioning. App Gateway picks up the new version automatically (you may need to bump the listener's SSL cert version pointer if you used a versioned reference; the template uses the unversioned secret URI so it auto-rolls).

### Self-signed → real cert (typical first swap)

1. Obtain a real cert for `<customDomain>` (Let's Encrypt, Azure Front Door managed cert, commercial CA, etc.).
2. Convert to PFX.
3. `az keyvault certificate import --vault-name <accountName>-kv --name teams-bot-tls --file new-cert.pfx --password <pwd>`.
4. The App Gateway picks up the new cert version within a few minutes. Force-refresh if needed:
   ```bash
   az network application-gateway ssl-cert update \
     -g <rg> --gateway-name <accountName>-appgw -n tls-cert \
     --key-vault-secret-id "https://<accountName>-kv.vault.azure.net/secrets/teams-bot-tls"
   ```

### Let's Encrypt via DNS-01 (any registrar)

DNS-01 is the most portable Let's Encrypt option — works with any registrar that lets you create TXT records, including the case where your domain points at an Azure IP.

The repo includes `scripts/obtain-letsencrypt-cert.ps1` as a starting point (it uses certbot with manual DNS-01 and IONOS as the example registrar). Adapt the `New-DnsTxtRecord` step for your DNS provider (Cloudflare, Route 53, Google Domains, etc.). The script automatically imports the resulting PFX to Key Vault.

### Let's Encrypt via HTTP-01 (after App Gateway is up)

If you don't have DNS-01 access but the App Gateway is reachable on the public internet, you can use HTTP-01. Briefly:
1. Add a temporary `http-listener` on port 80 to the App Gateway with a routing rule that serves `/.well-known/acme-challenge/*` from a small backend (e.g. an Azure Function or a static-IP VM).
2. Run `win-acme` or `certbot` HTTP-01 challenge for your domain.
3. Import the resulting PFX to Key Vault as `teams-bot-tls`.
4. Remove the temporary port-80 listener.

### nip.io domains specifically

nip.io cannot be validated via DNS-01 (you don't own the zone). You can use HTTP-01 against `<IP>.nip.io` as above, but most M365 admin policies flag nip.io as low-reputation — only useful for dev. For any real deployment, switch to a domain you own.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Agent doesn't respond in Teams | Cert chain rejected by Bot Channel Adapter | Swap self-signed cert for a CA-issued one (see [Cert rotation](#cert-rotation)) |
| `KeyBasedAuthenticationNotPermitted` during `azd provision` | Azure Policy blocks shared-key auth, breaking deploymentScript storage | Set `createTeamsTlsCert=false` and `deployTeamsPublishScript=false` and follow Phase 2 manually |
| `Received an unexpected EOF` calling Foundry data plane from outside VNet | Cognitive Services PE rejects TLS from sources outside VNet primary CIDR | Run the call from the jumpbox VM (`az vm run-command`) — never from a P2S VPN client or public host |
| `protocols[].protocol` value `ActivityProtocol` rejected | Foundry uses the enum value `Activity` (not `ActivityProtocol`) | Use `Activity`. The in-repo Bicep is fixed |
| App Gateway backend health = `Unhealthy` | APIM FQDN resolves to public IP, but APIM has private-only access | Use APIM private endpoint IP as backend pool address instead of FQDN |
| App Gateway 400 from Foundry | Missing `api-version` query param on the Activity Protocol call | APIM `rewrite-uri` policy must append `?api-version=2025-11-15-preview` — already in the template |
| APIM 401 on Bot messages | JWT validation failing | Confirm `botClientId` in APIM policy audience matches `defaultInstanceIdentity.clientId` of the Foundry App |
| APIM 404 on Bot messages | Path mismatch | APIM `bot-messaging` API must have `POST /*` operation with the rewrite-uri policy |
| App Gateway provisioning fails with `ApplicationGatewayWafConfigurationDeprecated` | Old `webApplicationFirewallConfiguration` block left in template | Use `firewallPolicy` only; the in-repo Bicep is fixed |
| App Gateway PIP rejected for AZ SKUs | PIP not zone-redundant | Recreate PIP with `--zone 1 2 3` and `--tier Regional` |
| Foundry portal Publish dialog can't see the Bot Service | Bot Service in a different RG / sub than the Foundry account | Bot Service must be in the same subscription; same RG is recommended |
| M365 admin approval never appears | Wrong scope or admin policy | Confirm **People in your organization** was selected and the user has the **M365 Admin** role |
| `MsaAppId is invalid` on Bot Service | `msaAppId` doesn't match Foundry App identity | Re-read the Foundry App's `defaultInstanceIdentity.clientId` and update `BOT_CLIENT_ID` env var, then `azd provision` |
| Login screen in Teams when chatting with bot | Auth flow is working | User completes Entra ID sign-in. No fix needed |
| Agent works in Foundry but not Teams | Outbound traffic blocked from agent runtime | Allow outbound to `smba.trafficmanager.net`, `login.microsoftonline.com`, `login.botframework.com` |

### Useful debugging commands

```bash
# App Gateway backend health (deep view)
az network application-gateway show-backend-health \
  --name <accountName>-appgw --resource-group <rg> \
  --query "backendAddressPools[0].backendHttpSettingsCollection[0].servers[0].{health:health,log:healthProbeLog}"

# APIM response codes for the last 5 min (look for spikes of 4xx)
az monitor metrics list \
  --resource "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ApiManagement/service/<accountName>apim" \
  --metric "Requests" --interval PT1M \
  --dimension "GatewayResponseCode" -o table

# End-to-end TLS reachability from the public internet
curl -vk https://<customDomain>/bot 2>&1 | head -40

# Direct Activity Protocol call (run from jumpbox / over VPN, with MI or user token)
TOKEN=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)
curl -X POST \
  "https://<account>.services.ai.azure.com/api/projects/<project>/applications/<app>/protocols/activityprotocol?api-version=2025-11-15-preview" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"type":"message","text":"test"}'
```

---

## Firewall rules

If your network controls outbound traffic, allow these FQDNs:

| FQDN | Purpose |
|---|---|
| `smba.trafficmanager.net` | Bot reply endpoint (agent → Teams) |
| `login.microsoftonline.com` | Entra ID token acquisition |
| `login.botframework.com` | Bot Framework OIDC metadata |

For inbound to the App Gateway, restrict source IPs to the `AzureBotService` service tag from the [Azure IP Ranges file](https://www.microsoft.com/en-us/download/details.aspx?id=56519).

---

## Security reference

| Layer | Control |
|---|---|
| **Network perimeter** | WAF v2 on Application Gateway; AzureBotService IP restriction at NSG / App Gateway WAF |
| **TLS** | Terminated at App Gateway with your cert in Key Vault |
| **Authentication** | Microsoft-signed JWT validated at APIM |
| **Authorization** | JWT audience locked to your Bot Client ID |
| **Agent isolation** | Foundry account on private endpoint, unreachable from public internet |
| **Outbound** | Limited to specific Microsoft FQDNs |
| **Identity** | Published agent uses its own Entra agent identity (`defaultInstanceIdentity`) |

---

## Optional: download-and-customize the Teams manifest

If you choose **Download & customize** in the Foundry portal Publish dialog instead of **Direct publish**, the portal hands you a `.zip` with a Teams app manifest. The manifest format roughly:

```json
{
  "$schema": "https://developer.microsoft.com/en-us/json-schemas/teams/v1.17/MicrosoftTeams.schema.json",
  "manifestVersion": "1.17",
  "version": "1.0.0",
  "id": "<bot-client-id>",
  "developer": {
    "name": "Your Org",
    "websiteUrl": "https://yourcompany.com",
    "privacyUrl": "https://yourcompany.com/privacy",
    "termsOfUseUrl": "https://yourcompany.com/terms"
  },
  "name": { "short": "Marketing Pipeline", "full": "Marketing Pipeline AI Agent" },
  "description": {
    "short": "AI-powered marketing content pipeline",
    "full": "Sequential workflow that analyses a product, writes marketing copy, and polishes the final output."
  },
  "icons": { "outline": "outline.png", "color": "color.png" },
  "accentColor": "#0078D4",
  "bots": [
    {
      "botId": "<bot-client-id>",
      "scopes": ["personal", "team", "groupChat"]
    }
  ]
}
```

Sideload it in Microsoft Teams: **Apps** → **Manage your apps** → **Upload an app** → **Upload a custom app**. For org-wide distribution, **Submit an app to your org** instead — that triggers admin approval the same way as Direct publish with **People in your organization** scope.

---

## Related

- [Microsoft Foundry — Publish agents to M365 and Teams](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/publish-copilot)
- [Container-hosted agent track (FoundryA365 sample)](https://github.com/microsoft-foundry/foundry-samples/tree/main/samples/csharp/FoundryA365)
- [Foundry agents through the corporate firewall (blog)](https://techcommunity.microsoft.com/blog/azure-ai-foundry-blog/foundry-agents-and-custom-engine-agents-through-the-corporate-firewall/4502218)
- This template's other docs: [README.md](README.md), [PrivateDeploy.md](PrivateDeploy.md), [diagrams/architecture.md](diagrams/architecture.md)
