# Debugging the Teams ↔ Foundry agent path

When messages stop flowing between Teams and your Foundry agent, the failure is almost always at one of six hops. This guide walks each hop top-down with: **what to configure for visibility**, **how to inspect it**, and **the most common failure mode at that layer**.

```
1. Teams client     ──────────────►  Microsoft Bot Channel Adapter
2. Bot Service      ◄──signed JWT──  Bot Channel Adapter
3. App Gateway       (WAF + TLS)
4. APIM bot-messaging API  (JWT validate, rewrite-uri)
5. Foundry Agent Application Activity Protocol endpoint  (private)
6. Workflow / prompt agent + Azure OpenAI deployment
```

---

## 0. One-time: turn on diagnostic logging

> **TL;DR — already done if you deployed with `deployDiagnosticSettings=true` (default).** Skip to Section 1.

This template ships a `diagnostic-settings.bicep` module that wires the four debug-critical resources into the Log Analytics workspace deployed by `application-insights.bicep`. It also creates the APIM-API-level App Insights tracing logger so the `bot-messaging` API can be debugged per-request from the APIM Test blade.

The module is invoked from `main.bicep` and is **on by default** (`deployDiagnosticSettings=true`). It is skipped if `deployApplicationInsights=false` (because the destination workspace wouldn't exist).

What it wires up:

| Resource | Diagnostic categories enabled | KQL table populated |
|---|---|---|
| Application Gateway | All logs (Access / Performance / Firewall) + AllMetrics | `AGWAccessLogs`, `AGWFirewallLogs`, `AGWPerformanceLogs` |
| API Management | All logs (GatewayLogs / WebSocketConnectionLogs) + AllMetrics | `ApiManagementGatewayLogs`, `ApiManagementWebSocketConnectionLogs` |
| Bot Service | `BotRequest` + AllMetrics | `AzureDiagnostics` (filter `ResourceType=="BOTSERVICES"`) |
| Foundry (Cognitive Services) account | All logs (Audit / RequestResponse / Trace) + AllMetrics | `AzureDiagnostics` (filter `ResourceProvider=="MICROSOFT.COGNITIVESERVICES"`) |
| APIM logger + `bot-messaging` API tracing | App Insights logger + per-API diagnostics (sampling 100%, allErrors, W3C correlation) | `AppRequests`, `AppDependencies`, `AppTraces` |

Logs start flowing within ~5 minutes.

### If you need to enable them manually after the fact

If you have an existing deployment without diagnostic settings (e.g. you initially deployed with `deployDiagnosticSettings=false`), you can either:

**Option A — Redeploy with the flag on:**

```bash
azd env set DEPLOY_DIAGNOSTIC_SETTINGS true
azd provision
```

The diagnostic-settings module is idempotent and finishes in ~30 seconds.

**Option B — Run the equivalent CLI commands directly:**

```bash
RG=rg-foundry-hybrid-private-02
LAW="/subscriptions/<sub>/resourceGroups/$RG/providers/Microsoft.OperationalInsights/workspaces/<accountName>appinsights-law"
APPGW="/subscriptions/<sub>/resourceGroups/$RG/providers/Microsoft.Network/applicationGateways/<accountName>-appgw"
APIM="/subscriptions/<sub>/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/<accountName>apim"
BOT="/subscriptions/<sub>/resourceGroups/$RG/providers/Microsoft.BotService/botServices/<applicationName>-bot"
ACC="/subscriptions/<sub>/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/<accountName>"

for RES in $APPGW $APIM $BOT $ACC; do
  az monitor diagnostic-settings create --name to-law --resource $RES \
    --workspace $LAW \
    --logs '[{"categoryGroup":"allLogs","enabled":true}]' \
    --metrics '[{"category":"AllMetrics","enabled":true}]'
done
```

> **Why no storage destination?** Auto-provisioned diagnostic-settings storage uses shared-key auth, which many subscriptions block via Azure Policy. Log Analytics is sufficient for the queries in this doc.

---

## 1. Teams client → Bot Channel Adapter

**Symptom:** typing in the agent chat produces no reply, no error, no "..."  spinner stuck.

**Quick checks:**
- The agent appears in Teams under **Apps** → **Manage your apps** → **Built for your org** (or **Manage your apps** for sideloads). If it doesn't appear, see [`docs/teams-app-onboarding.md`](teams-app-onboarding.md) Step 3-5.
- Try **Teams web** (https://teams.microsoft.com) in a private/incognito window. Eliminates desktop-client caching and corporate proxy intermediation.
- Check the bot via the Bot Service **Test in Web Chat** blade in the Azure Portal. If Web Chat works but Teams doesn't, the **Teams Channel** is misconfigured (re-add it: Bot Service → Channels → delete Teams → add Teams → Save).

**Diagnostic surfaces:** none on the client side. Move to Bot Service.

---

## 2. Azure Bot Service

This is the most common failure point because cert/endpoint validation lives here.

### Required configuration

| Setting | Required value | Why |
|---|---|---|
| `kind` | `azurebot` | The only kind that supports Teams Channel + Foundry Activity Protocol relay |
| `sku.name` | `S1` (Standard) | Free SKU does NOT support Teams Channel |
| `properties.msaAppId` | Foundry App `defaultInstanceIdentity.clientId` | Channel Adapter signs JWTs with this id; APIM's audience claim must match |
| `properties.msaAppType` | `SingleTenant` | The Foundry App identity is single-tenant |
| `properties.msaAppTenantId` | Your tenant id | Required for `SingleTenant` |
| `properties.endpoint` | `https://<customDomain>/bot` | Must match the App Gateway listener's host header |
| `properties.publicNetworkAccess` | `Enabled` | Private Link not supported for Bot Service per [the Learn doc](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/publish-copilot#limitations) |
| Teams Channel | `isEnabled: true` | Created at `/channels/MsTeamsChannel` |

Verify all of the above:

```bash
RG=<rg>; BOT=<applicationName>-bot
az resource show -g $RG --resource-type Microsoft.BotService/botServices -n $BOT \
  --query "{kind:kind, sku:sku.name, appId:properties.msaAppId, appType:properties.msaAppType, tenantId:properties.msaAppTenantId, endpoint:properties.endpoint, public:properties.publicNetworkAccess}" -o json

az rest --method get \
  --uri "https://management.azure.com/subscriptions/<sub>/resourceGroups/$RG/providers/Microsoft.BotService/botServices/$BOT/channels?api-version=2022-09-15" \
  --query "value[].{name:name, enabled:properties.properties.isEnabled}" -o table
```

### Most common failures

| Symptom | Cause | Fix |
|---|---|---|
| Bot doesn't show in Teams at all after Channel enabled | Tenant has Teams custom-app upload disabled | Teams Admin Center → Org-wide app settings → enable custom apps |
| Bot in Teams chat shows error "Sorry, an error occurred" | Endpoint URL unreachable from Bot Channel Adapter | curl from outside: `curl https://<customDomain>/bot` should return 401 (not connection refused / cert error) |
| 401 from Bot Service "Sorry, my bot code is having an issue" | TLS cert chain invalid (self-signed) | Swap cert — see [PUBLISH.md Cert rotation](../PUBLISH.md#cert-rotation) |
| Bot replies via Web Chat but not Teams | Teams Channel was added before Bot Service `msaAppId` was set | Delete and re-add Teams Channel |
| Intermittent failures, "service is having trouble" | Bot Service throttling (default 4 req/sec) | Open support case or move to higher SKU |

### Bot Service request logs (after Step 0)

```kql
AzureDiagnostics
| where ResourceType == "BOTSERVICES" and Category == "BotRequest"
| where TimeGenerated > ago(1h)
| project TimeGenerated, OperationName, ResultType, DurationMs, Channel = channel_s, Activity = activityType_s, ResultDescription
| order by TimeGenerated desc
```

If you see `ResultType != Success` here, that's the Channel Adapter's view — its rejection means it never even tried your endpoint. If `ResultType == Success` here but the user sees nothing, the failure is downstream (App Gateway or APIM).

### Self-test the bot endpoint

```bash
# Should return HTTP 401 (challenge succeeded — JWT validation works, request was rejected because no token)
curl -X POST https://<customDomain>/bot \
  -H "Content-Type: application/json" \
  -d '{"type":"message","text":"test"}' -s -o /dev/null -w "%{http_code}\n"
```

Expected: `401`. If `502` or `503` → App Gateway / APIM has a backend health problem (Step 3/4). If `200` → JWT validation is disabled (security issue, but not a functional issue for Teams).

---

## 3. Application Gateway

### Required configuration

| Setting | Value | Why |
|---|---|---|
| SKU | `WAF_v2` | TLS + WAF in one tier; only WAF_v2 supports current SSL policies |
| Public IP | Static, Standard, zone-redundant `[1,2,3]` | AZ SKU requirement |
| Frontend port | `443` | HTTPS only |
| SSL cert | Referenced from Key Vault, unversioned secret URI | Auto-rolls when a new cert version is imported |
| HTTP listener | Hostname = `<customDomain>` (NOT the IP) | SNI required for cert presentation |
| Backend pool | APIM **private IP** (NOT FQDN) when APIM has `publicNetworkAccess: Disabled` | FQDN resolves to public IP via global DNS |
| HTTP settings | Probe accepts 200-404 (APIM returns 404 on `/status-0123456789abcdef`) | Default probe is too strict |
| WAF policy | OWASP 3.2, Prevention mode | Detection mode lets attacks through |

Verify:

```bash
RG=<rg>; AG=<accountName>-appgw
az network application-gateway show -g $RG -n $AG \
  --query "{state:provisioningState, op:operationalState, sku:sku.name,
           listener:httpListeners[0].{name:name, hostName:hostName, sslCert:sslCertificate.id},
           sslCert:sslCertificates[0].keyVaultSecretId,
           backendPool:backendAddressPools[0].{name:name, addresses:backendAddresses[].{fqdn:fqdn, ip:ipAddress}},
           probe:probes[0].{path:path, status:match.statusCodes}}" -o json
```

Expected:
- `state=Succeeded`, `op=Running`
- `sslCert.keyVaultSecretId` points at `…/secrets/teams-bot-tls`
- Backend pool address is APIM's **private IP** (192.168.x.x), not the `.azure-api.net` FQDN

### Backend health (real-time)

```bash
az network application-gateway show-backend-health -g $RG -n $AG \
  --query "backendAddressPools[].backendHttpSettingsCollection[].servers[].{server:address,health:health,reason:healthProbeLog}" -o table
```

`Healthy` is what you want. `Unhealthy` with reason `Status code of the response from the backend server didn't match the expected status codes` usually means the probe is too strict — match codes must include `404` because APIM's default path returns it.

### Access log

```kql
AGWAccessLogs
| where TimeGenerated > ago(1h)
| where requestUri_s startswith "/bot"
| project TimeGenerated, clientIP_s, httpMethod_s, requestUri_s, httpStatus_d, backendIPAddress_s, timeTaken_d, sslEnabled_s, sslCipher_s
| order by TimeGenerated desc
| take 50
```

Reading the columns:
- `httpStatus_d` of **502** → backend unreachable (APIM down or wrong IP)
- **504** → backend timed out (Foundry slow or unreachable)
- **403** → WAF blocked the request (see firewall log below)
- **401** → APIM rejected JWT (this is the "good" path for an unauthenticated probe)
- **200** → end-to-end success

### WAF firewall log (when 403s appear)

```kql
AGWFirewallLogs
| where TimeGenerated > ago(1h) and action_s == "Blocked"
| project TimeGenerated, ruleId_s, message_s, transactionId_s, requestUri_s, hostName_s
| order by TimeGenerated desc
```

OWASP false positives on Bot Framework activity payloads are rare but possible. If you see false positives, add a per-rule exclusion in the WAF policy (NOT a global mode switch).

### Most common failures at this layer

| Symptom | Diagnosis |
|---|---|
| `op=Stopped` | App Gateway hit a critical cert/config error; check Activity Log |
| `op=Running` but `state=Updating` for >30 min | A config change is stuck; sometimes the only fix is `az network application-gateway stop` then `start` |
| `Unhealthy` backend, probe says `Common Name (CN) of the leaf certificate presented by the backend doesn't match the host header` | SNI mismatch; set `--host-name <apimName>.azure-api.net` on the HTTP settings |
| `Unhealthy` backend, `Connection refused` | APIM private IP changed (PE moved) — re-look up and update the backend pool |
| Listener serves an old cert after `az keyvault certificate import` | Force-refresh: `az network application-gateway ssl-cert update` then `stop`/`start` |

---

## 4. APIM bot-messaging API

### Required configuration

| Element | Setting | Why |
|---|---|---|
| API path | `bot` | Matches Bot Service endpoint `/bot` |
| Operation | `POST /*` | Catch-all for Bot Framework activities |
| Inbound policy | `validate-jwt` block + `rewrite-uri` | Token enforcement + Foundry api-version |
| JWT `audiences` | The Bot client id | Must match `msaAppId` |
| JWT `issuers` | `https://api.botframework.com` | Microsoft Bot Framework's issuer |
| JWT `openid-config` | `https://login.botframework.com/v1/.well-known/openidconfiguration` | Public OIDC metadata |
| `rewrite-uri template` | `/?api-version=2025-11-15-preview` | Activity Protocol requires this query string |
| `serviceUrl` (backend) | Activity Protocol URL on the Foundry account | Where the call actually goes |

Verify:

```bash
APIM=<accountName>apim
az apim api show -g $RG --service-name $APIM --api-id bot-messaging \
  --query "{path:path, serviceUrl:serviceUrl, protocols:protocols}" -o json

# Operations
az rest --method get \
  --uri "https://management.azure.com/subscriptions/<sub>/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM/apis/bot-messaging/operations?api-version=2024-05-01" \
  --query "value[].{name:name, method:properties.method, urlTemplate:properties.urlTemplate}" -o table

# Inbound policy (look for validate-jwt + rewrite-uri)
az rest --method get \
  --uri "https://management.azure.com/subscriptions/<sub>/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM/apis/bot-messaging/policies/policy?api-version=2024-05-01" \
  --query "properties.value" -o tsv
```

### Gateway log

```kql
ApiManagementGatewayLogs
| where TimeGenerated > ago(1h) and ApiId == "bot-messaging"
| project TimeGenerated, Method, Url, ResponseCode, BackendResponseCode, TotalTime, RequestSize, ResponseSize, OperationId, CorrelationId, ErrorReason, IsRequestSuccess
| order by TimeGenerated desc
| take 50
```

Reading:
- `ResponseCode == 401` and `BackendResponseCode == 0` → APIM rejected JWT, didn't call backend. Check `ErrorReason`.
- `ResponseCode == 200` and `BackendResponseCode == 200` → end-to-end OK
- `ResponseCode == 500` and `BackendResponseCode == 0` → policy error (malformed JWT block, etc.)
- `ResponseCode == 502/503` and `BackendResponseCode == 0` → backend (Foundry) unreachable
- `BackendResponseCode == 400` → Foundry rejected the call (usually missing `api-version` query — rewrite-uri broken)
- `BackendResponseCode == 404` → APIM serviceUrl is wrong (Activity Protocol path mismatch)

### Test JWT validation locally

You don't need a real Bot token to test the JWT path — just any token works because validation looks at signature + issuer + audience.

```bash
# Mint a fake token (will fail signature but APIM tells you exactly which check failed)
FAKE_JWT=$(printf '{"alg":"RS256","typ":"JWT"}' | base64 -w0).$(printf '{"iss":"https://api.botframework.com","aud":"<bot-client-id>","exp":99999999999}' | base64 -w0).fake

curl -X POST https://<customDomain>/bot \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $FAKE_JWT" \
  -d '{}' -s -o /dev/null -w "%{http_code}\n"
```

Expected: `401` with response body explaining "signature validation failed". A `200` here means JWT validation is broken; a `5xx` means the policy itself has a syntax error.

### Most common failures

| Symptom | Cause |
|---|---|
| `401 Unauthorized — Invalid Bot token` for real Teams traffic | `audiences` in policy doesn't match Bot Service `msaAppId` |
| `400` from Foundry backend | `rewrite-uri` policy missing or wrong — must end with `?api-version=2025-11-15-preview` |
| `404` from Foundry backend | API `serviceUrl` doesn't end with `/protocols/activityprotocol` |
| `502` from APIM | Foundry private endpoint dropped, or APIM not in VNet anymore |

---

## 5. Foundry Agent Application Activity Protocol endpoint

This is the data-plane endpoint on the private Foundry account that the agent listens on.

### Required configuration

| Element | Value | Verify with |
|---|---|---|
| Agent Application exists | `applications/<applicationName>` returns 200 | `az rest GET ...applications/<applicationName>?api-version=2026-01-15-preview` |
| Agent Deployment has `Activity` protocol | `protocols[].protocol == "Activity"` (NOT `ActivityProtocol`) | Same GET |
| Agent Deployment `state == Running` | | Same GET |
| Agent Deployment `provisioningState == Succeeded` | | Same GET |
| `defaultInstanceIdentity.clientId` is non-empty | This is what Bot Service's `msaAppId` must be set to | Same GET |
| Foundry account `publicNetworkAccess` | `Enabled` with `networkAcls.defaultAction=Deny` and `bypass=AzureServices` (this template's default) — OR `Disabled` with private endpoint reachable from APIM subnet | `az cognitiveservices account show` |
| `networkInjections` configured for `scenario=agent` | Points at `agent-subnet` | Same |
| Account capability host | Auto-created by backend when networkInjections set | `az rest GET ...capabilityHosts?api-version=2025-04-01-preview` |
| Project capability host | `kind=Agents`, `provisioningState=Succeeded` | Same scoped to project |

Verify the application + deployment from the **jumpbox** (the public CLI can read ARM but data-plane calls to the Foundry FQDN will be blocked from the public internet for a private account):

```powershell
# Run on the jumpbox via `az vm run-command`
function MsiToken { (Invoke-RestMethod -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com" -Headers @{Metadata="true"}).access_token }
$arm = MsiToken
$base = "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<account>/projects/<project>"

$app = Invoke-RestMethod -Uri "$base/applications/<applicationName>?api-version=2026-01-15-preview" -Headers @{Authorization="Bearer $arm"}
$app.properties | Select-Object provisioningState, baseUrl, displayName, agents, defaultInstanceIdentity

$dep = Invoke-RestMethod -Uri "$base/applications/<applicationName>/agentdeployments/<deploymentName>?api-version=2026-01-15-preview" -Headers @{Authorization="Bearer $arm"}
$dep.properties | Select-Object state, provisioningState, protocols, agents
```

### Send a synthetic Activity message directly (bypasses Bot Service + App Gateway + APIM)

```powershell
# On the jumpbox — uses MI auth, hits the private endpoint directly
$ai = (Invoke-RestMethod -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fai.azure.com" -Headers @{Metadata="true"}).access_token
$activity = @{
    type = "message"
    text = "Hello synthetic test"
    from = @{ id = "test-user"; name = "Test" }
    recipient = @{ id = "bot"; name = "Bot" }
    conversation = @{ id = [guid]::NewGuid().ToString() }
    serviceUrl = "https://smba.trafficmanager.net/uk/"
    channelId = "msteams"
    id = [guid]::NewGuid().ToString()
} | ConvertTo-Json -Depth 6
Invoke-RestMethod -Uri "https://<account>.services.ai.azure.com/api/projects/<project>/applications/<applicationName>/protocols/activityprotocol?api-version=2025-11-15-preview" `
    -Method Post -Headers @{Authorization="Bearer $ai"; "Content-Type"="application/json"} -Body $activity
```

A `202 Accepted` or `200 OK` means Foundry accepted the activity. A `400` means the activity payload is malformed; a `401` means MI tokens aren't accepted (Foundry expects Bot Framework JWTs for this endpoint — see below).

### Important: this endpoint only accepts **Bot Framework signed JWTs**

Even with a managed identity / user token that works elsewhere on Foundry, the Activity Protocol endpoint validates Bot Framework signing (issuer `https://api.botframework.com`). Synthetic tests are useful for "is the endpoint reachable" not "does my auth chain work" — for the latter, end-to-end Teams traffic is the only realistic test.

### Most common failures

| Symptom | Cause |
|---|---|
| 400 from this endpoint, "definition field is required" | You're calling `agentdeployments PUT` not the Activity Protocol POST |
| 400 from this endpoint, "Error converting value 'ActivityProtocol'..." | Used wrong enum — must be `Activity` not `ActivityProtocol`. Fixed in this template |
| 401 here even from jumpbox MI | Endpoint expects Bot Framework JWT — synthetic MI tests will always 401 here; rely on end-to-end testing instead |
| 403 `preview_feature_required: WorkflowAgents=V1Preview` | The workflow agent itself needs the opt-in header at creation time. After the agent is created it runs without the header |

---

## 6. The agent itself (workflow / prompt + model deployment)

### Required configuration

For the `marketing-pipeline` workflow agent specifically:
- 3 prompt sub-agents must exist: `marketing-analyst`, `marketing-copywriter`, `marketing-editor` — all v1+
- The model named in each sub-agent's `definition.model` (default `gpt-4o-mini`) must have an active deployment on the account
- The model deployment SKU must support the project's capability host (current template default: `GlobalStandard`)

Verify model deployment health:

```bash
az cognitiveservices account deployment list -g $RG -n <accountName> \
  --query "[].{name:name, model:properties.model.name, version:properties.model.version, state:properties.provisioningState, sku:sku.name, capacity:sku.capacity}" -o table
```

Verify the agent + sub-agents exist (jumpbox):

```powershell
$ai = (Invoke-RestMethod -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fai.azure.com" -Headers @{Metadata="true"}).access_token
$base = "https://<account>.services.ai.azure.com/api/projects/<project>"
$agents = Invoke-RestMethod -Uri "$base/agents?api-version=v1" -Headers @{Authorization="Bearer $ai"}
$agents.value | Select-Object name, kind, latestVersion
```

Expected output:
```
name                  kind     latestVersion
----                  ----     -------------
marketing-analyst     prompt   1
marketing-copywriter  prompt   1
marketing-editor      prompt   1
marketing-pipeline    workflow 1
```

### Test the agent in isolation (Foundry portal)

The fastest way to confirm "is the agent itself working" — bypassing Teams, App Gateway, and APIM entirely:

1. Open https://ai.azure.com → project → **Agents** → `marketing-pipeline`.
2. Click **Try in playground** in the top right.
3. Send a test message like `Smart water bottle that tracks hydration`.
4. Watch the workflow execute through analyst → copywriter → editor.

If this works but Teams doesn't, the failure is in one of layers 1-5. If this also fails, the agent itself is broken — see App Insights below.

### Application Insights traces

The template wires Application Insights to the project. To query:

```kql
// Agent invocations
AppDependencies
| where TimeGenerated > ago(1h)
| where Name contains "invoke_agent" or Name contains "chat"
| project TimeGenerated, Name, DurationMs, Success, ResultCode, OperationName, AppRoleName
| order by TimeGenerated desc

// Model calls (Azure OpenAI / APIM gateway)
AppDependencies
| where TimeGenerated > ago(1h)
| where Type == "Http" and Target contains "azure-api.net"
| project TimeGenerated, Name, Target, DurationMs, ResultCode, Success
| order by TimeGenerated desc

// Tool calls (AI Search, MCP, etc.)
AppDependencies
| where TimeGenerated > ago(1h) and Name has "tool"
| project TimeGenerated, Name, DurationMs, Success, ResultCode
| order by TimeGenerated desc

// Exceptions
AppExceptions
| where TimeGenerated > ago(1h)
| project TimeGenerated, ProblemId, OuterMessage, AppRoleName
| take 50
```

### Common agent-layer failures

| Symptom | Diagnosis |
|---|---|
| Agent runs but model call returns 429 | Model deployment capacity (`sku.capacity`) too low |
| Agent runs but model call returns 401/403 | APIM gateway connection auth broken — re-check the project's `apim-gateway` connection key |
| Workflow runs partially, stops at one sub-agent | That sub-agent's `model` value is wrong (or the model deployment was deleted) |
| 403 `preview_feature_required` at agent-create time | Missing `Foundry-Features: WorkflowAgents=V1Preview` header |
| 404 on agent endpoint | Wrong api-version (`v1` is current — older `2024-*` ones return 404 for new agent kinds) |

---

## Recipe: when chat is silent and you don't know where to start

Run these in order from your local terminal (where the cert chain works publicly):

```bash
RG=<rg>; AG=<accountName>-appgw; APIM=<accountName>apim; BOT=<applicationName>-bot
DOMAIN=<customDomain>
SUB=<sub>

# (1) Cert presented + chain ok
openssl s_client -connect <pip>:443 -servername $DOMAIN </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates

# (2) Listener returns 401 to unauthenticated POST  (means App Gateway + APIM + JWT validation are wired up)
curl -X POST https://$DOMAIN/bot -H "Content-Type: application/json" -d '{}' -s -o /dev/null -w "%{http_code}\n"

# (3) App Gateway backend health
az network application-gateway show-backend-health -g $RG -n $AG --query "backendAddressPools[].backendHttpSettingsCollection[].servers[].health" -o tsv

# (4) APIM bot-messaging API points at the right Foundry endpoint
az apim api show -g $RG --service-name $APIM --api-id bot-messaging --query serviceUrl -o tsv

# (5) Bot Service config matches Foundry
az resource show -g $RG --resource-type Microsoft.BotService/botServices -n $BOT --query "{endpoint:properties.endpoint, appId:properties.msaAppId}" -o json
# msaAppId should equal the Foundry App's defaultInstanceIdentity.clientId from layer 5

# (6) Teams channel enabled
az rest --method get --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.BotService/botServices/$BOT/channels?api-version=2022-09-15" \
  --query "value[?contains(name, 'MsTeams')].properties.properties.isEnabled" -o tsv

# (7) Recent App Gateway access log entries for /bot path
az monitor log-analytics query \
  --workspace $(az monitor log-analytics workspace show -g $RG -n <accountName>appinsights-law --query customerId -o tsv) \
  --analytics-query 'AGWAccessLogs | where TimeGenerated > ago(15m) and requestUri_s startswith "/bot" | project TimeGenerated, httpStatus_d, backendIPAddress_s, timeTaken_d | order by TimeGenerated desc | take 10' \
  -o table

# (8) Recent APIM gateway log for bot-messaging
az monitor log-analytics query \
  --workspace $(az monitor log-analytics workspace show -g $RG -n <accountName>appinsights-law --query customerId -o tsv) \
  --analytics-query 'ApiManagementGatewayLogs | where TimeGenerated > ago(15m) and ApiId == "bot-messaging" | project TimeGenerated, ResponseCode, BackendResponseCode, ErrorReason, TotalTime | order by TimeGenerated desc | take 10' \
  -o table
```

The first row that's **not** the expected value tells you which layer failed.

| Row | Expected | If wrong → |
|---|---|---|
| (1) | Subject CN matches `$DOMAIN`, issuer ≠ subject | Cert layer — see [PUBLISH.md Cert rotation](../PUBLISH.md#cert-rotation) |
| (2) | `401` | `502`/`504` = backend; `400` = listener config; `200` = JWT bypassed |
| (3) | `Healthy` | App Gateway → APIM is broken |
| (4) | Ends with `/protocols/activityprotocol` | Re-deploy `teamsInfra` module or PATCH the API |
| (5) | endpoint matches `https://$DOMAIN/bot`, appId is a GUID | Bot Service mis-wired |
| (6) | `true` | Re-add Teams Channel |
| (7) | Has rows with `httpStatus_d=401` for unauthenticated probes, `200` for real traffic | No rows = diag setting not on yet (do Step 0) |
| (8) | `ResponseCode=200` for real traffic, `BackendResponseCode=200` | Layer 5/6 — check Foundry agent traces |

---

## Useful Azure Portal blades for live debugging

| What you want to see | Where |
|---|---|
| Bot Service test conversation | Bot Service → Settings → **Test in Web Chat** |
| Bot Service channel health | Bot Service → Channels → click **Microsoft Teams** |
| App Gateway live backend health | App Gateway → Monitoring → **Backend health** |
| App Gateway insights (graphs) | App Gateway → Insights |
| APIM trace tool (per-request) | APIM → APIs → bot-messaging → **Test** → enable trace, send request |
| Foundry agent traces | https://ai.azure.com → project → **Tracing** |
| Application Insights end-to-end transaction | App Insights → Investigate → **Transaction search** |

---

## Related

- [`PUBLISH.md`](../PUBLISH.md) — provisioning runbook (Phases 1-3)
- [`docs/teams-app-onboarding.md`](teams-app-onboarding.md) — Teams app onboarding (Phase 4)
- [Microsoft Foundry — Publish agents to M365 and Teams](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/publish-copilot)
- [Bot Framework JWT validation reference](https://learn.microsoft.com/azure/bot-service/rest-api/bot-framework-rest-connector-authentication)
- [APIM gateway logs reference](https://learn.microsoft.com/azure/api-management/api-management-howto-use-azure-monitor)
