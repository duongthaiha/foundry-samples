# Teams publish — `metadata` 16-property cap troubleshooting

## TL;DR

If a Foundry agent published to Microsoft Teams fails on **every** message with:

```
invalid_request_error … object_above_max_properties …
Invalid 'metadata': too many properties.
Expected an object with at most 16 properties, but got an object with 17 properties instead.
```

…the most likely cause is that the Agent Application's **Managed Deployment** was created with only the `Responses` protocol registered. The Bot Service still hits the Activity Protocol endpoint, but with no `Activity` translator the bridge serializes the entire Bot Framework Activity envelope into the Responses `metadata` field (17+ top-level keys), which trips the OpenAI 16-property cap.

The fix is a one-line property change: re-register the deployment with **both** `Responses` and `Activity` protocols. Use [`Patch-DeploymentProtocols.ps1`](./Patch-DeploymentProtocols.ps1).

## How `metadata` is set and passed through

Three layers merge into the single `metadata` object on every `POST /api/projects/{p}/responses` request:

```
                ┌─────────────────────────────────────────────────────┐
 user types →   │  Teams client  →  Bot Service (Activity Protocol)   │
 in Teams       └──────────────────────────┬──────────────────────────┘
                                           │  Activity envelope:
                                           │    activity.id
                                           │    activity.channelId
                                           │    activity.conversation.id
                                           │    activity.conversation.tenantId
                                           │    activity.from.aadObjectId
                                           │    activity.recipient.id
                                           │    activity.serviceUrl
                                           │    activity.locale
                                           │    activity.channelData.team.id
                                           │    activity.channelData.channel.id
                                           │    activity.channelData.tenant.id
                                           │    activity.replyToId
                                           ▼
            ┌──────────────────────────────────────────────────────────┐
            │  Foundry Agent Application — Managed Deployment          │
            │  protocols = [ Responses 1.0,  Activity 1.0 ]            │ ← LAYER 1
            │  Activity-Protocol translator maps activity-envelope     │   bridge contribution
            │  fields onto Responses inputs (NOT into metadata)        │
            │  WHEN the Activity protocol is registered.               │
            │                                                          │
            │  If Activity protocol is MISSING, the bridge falls back  │   ⚠ ROOT CAUSE
            │  to a generic serializer that flattens the activity into │
            │  metadata — 17+ top-level keys, instant failure.         │
            └──────────────────────────┬───────────────────────────────┘
                                       │
                                       ▼
            ┌──────────────────────────────────────────────────────────┐
            │  Agent version definition (Build tab in portal)          │ ← LAYER 2
            │    agent.metadata          ← author-supplied             │   author contribution
            │    agent.tools[].metadata                                │
            │    agent.workflow.steps[].metadata                       │
            └──────────────────────────┬───────────────────────────────┘
                                       │
                                       ▼
            ┌──────────────────────────────────────────────────────────┐
            │  Per-turn additional_metadata (rare; if a caller sets it)│ ← LAYER 3
            └──────────────────────────┬───────────────────────────────┘
                                       │
                                       ▼
            POST {foundry}/api/projects/{p}/responses
            body.metadata = union(LAYER1, LAYER2, LAYER3)
                                       │
                                       ▼
                Responses validator: reject if top-level keys > 16
```

The validator counts **top-level keys only**. Nested objects don't recurse. The cap is `16 keys, key ≤ 64 chars, value ≤ 512 chars`.

## Root cause (the customer-observed case)

| Layer | Expected behaviour | Observed in failing deployment |
|---|---|---|
| 1 — Managed Deployment protocols | `["Responses", "Activity"]` | `["Responses"]` only — translator missing |
| 1 — Bridge contribution to `metadata` | 0 keys (translator maps to Responses inputs) | 17 keys (entire Activity envelope flattened) |
| 2 — Author metadata on agent | ≤ 8 keys recommended | 1 key (`logo`) — not the offender |
| 3 — Per-call `additional_metadata` | 0 keys | 0 keys |

The Bot Service `endpoint` (`…/protocols/activityprotocol?api-version=…`) is wired correctly. The endpoint exists on the application even when `Activity` isn't in `protocols`; that's what allows the fallback serializer to run and produce the failing payload.

## Fix

Re-register the Managed Deployment with both protocols:

```json
"protocols": [
  { "protocol": "Responses", "version": "1.0" },
  { "protocol": "Activity",  "version": "1.0" }
]
```

Apply via PowerShell with [`Patch-DeploymentProtocols.ps1`](./Patch-DeploymentProtocols.ps1), or via Bicep — see the reference module [`teams-agent-publish-script.bicep`](../../modules-network-secured/teams-agent-publish-script.bicep) lines 130-133:

```bicep
protocols = @(
  @{ protocol = "Responses"; version = "1.0" }
  @{ protocol = "Activity";  version = "1.0" }
)
```

If you author the deployment as a typed ARM/Bicep resource (`Microsoft.CognitiveServices/accounts/projects/applications/agentDeployments`), include both protocol entries in `properties.protocols`.

## How to run `Patch-DeploymentProtocols.ps1`

### Prerequisites

1. **PowerShell 7+** (Windows, macOS, or Linux). Check with `pwsh --version`.
2. **Azure CLI** installed and on PATH. Check with `az --version`.
3. **Az role** on the project: *Cognitive Services Contributor* (or *AI Foundry Contributor*, or *Contributor* on the resource group). The script PUTs an `agentDeployments` resource.
4. **Sign in to the right tenant + subscription**:

   ```powershell
   az login --tenant <tenant-guid>
   az account set --subscription <subscription-guid>
   az account show --query "{sub:id, tenant:tenantId, user:user.name}" -o table
   ```

### Step 1 — Find the parameter values

You need: `SubscriptionId`, `ResourceGroup`, `Account`, `Project`, `Application`, `Deployment`.

The portal URL after publishing has the shape
`https://ai.azure.com/nextgen/r/<encodedSub>,<rg>,,<account>,<project>/build/agents/<agent>/build` —
the slugs `<rg>`, `<account>`, `<project>` are usable directly; resolve the subscription id with `az`.

Or list them from the CLI:

```powershell
$rg   = "rg-foundry-uk-public"             # your resource group
$acct = "foundry-hd-uk-public"             # your Foundry / AI Services account
$proj = "proj-default"                     # your project
$sub  = (az account show --query id -o tsv)

# Discover applications and deployments under the project
./Get-ApplicationDeployment.ps1 `
  -SubscriptionId $sub -ResourceGroup $rg `
  -Account $acct -Project $proj
```

The output lists each `Application: <name>` and inside it each `Deployment: <name>`, and warns when `Activity` is not registered — that's the deployment you need to patch. Application and Deployment names are typically the same as the agent name (e.g. `sample-agent`).

### Step 2 — Dry run with `-WhatIf`

```powershell
cd C:\Git\foundry-samples\infrastructure\infrastructure-setup-bicep\19-hybrid-private-resources-agent-setup\docs\metadata

./Patch-DeploymentProtocols.ps1 `
  -SubscriptionId $sub `
  -ResourceGroup  $rg `
  -Account        $acct `
  -Project        $proj `
  -Application    sample-agent `
  -Deployment     sample-agent `
  -WhatIf
```

This prints the current `protocols`, then the proposed PUT body, then `What if: Performing the operation "PUT protocols [Responses, Activity]" on target "sample-agent/sample-agent"` — but does not modify anything.

If the deployment is already correct, the script exits with `Both Responses and Activity protocols already registered. Nothing to do.`

### Step 3 — Apply the patch

Re-run without `-WhatIf` (add `-Verbose` if you want extra logging):

```powershell
./Patch-DeploymentProtocols.ps1 `
  -SubscriptionId $sub `
  -ResourceGroup  $rg `
  -Account        $acct `
  -Project        $proj `
  -Application    sample-agent `
  -Deployment     sample-agent
```

Expected output:

```
=== After PUT ===
provisioningState : Succeeded
state             : Running
[
  { "protocol": "Responses", "version": "1.0" },
  { "protocol": "Activity",  "version": "1.0" }
]
Done. Send a message from Teams to verify.
```

The change is effective immediately — no redeploy of the agent or Bot Service is needed.

### Step 4 — Confirm and verify

Re-run `Get-ApplicationDeployment.ps1` (same parameters) and confirm `protocols : Responses/1.0, Activity/1.0` with `OK: both Responses and Activity protocols are registered.` Then send a message from Teams (or Web Chat / Direct Line) to the bot.

### One-liner (if you already have a session signed in)

```powershell
./Patch-DeploymentProtocols.ps1 -SubscriptionId (az account show --query id -o tsv) -ResourceGroup rg-foundry-uk-public -Account foundry-hd-uk-public -Project proj-default -Application sample-agent -Deployment sample-agent
```

### Common errors

| Error | Cause | Fix |
|---|---|---|
| `Failed to acquire ARM token. Run 'az login' first.` | Not signed in or wrong tenant | `az login --tenant <tenant-guid>` |
| `AuthorizationFailed` on the GET / PUT | Caller lacks *Contributor* on the project | Grant *Cognitive Services Contributor* on the project (or RG) |
| `ResourceNotFound` on the deployment | Wrong Application or Deployment name | Run `Get-ApplicationDeployment.ps1` to list the real names |
| `Cannot find an overload for "ConvertTo-Json"` | Running on Windows PowerShell 5.1 | Use `pwsh` (PowerShell 7+) |
| Script exits with `Nothing to do.` | Both protocols already present | No action needed; cause is elsewhere — run `Get-AgentMetadataAudit.ps1` |

## Verification

1. Send a message to the bot from Teams (or Web Chat / Direct Line on the same Bot Service).
2. Confirm a normal agent reply.
3. If App Insights is wired to the Bot Service (`developerAppInsightsApplicationId`), the `/responses` dependency on the conversation's `operation_Id` should return `200` instead of `400`.

If failures persist:

- Re-GET the deployment via ARM (don't trust the portal cache) and verify both protocols are present.
- Confirm the agent has an active version and `agents[].agentVersion` on the deployment matches.
- Run [`Get-AgentMetadataAudit.ps1`](./Get-AgentMetadataAudit.ps1) to make sure Layer 2 isn't also over-budget.
- File a support ticket with subscription id, resource group, account/project/application/deployment names, `ms-cv`, `ConversationId`, and the ARM GET response on the deployment.

## Prevention

- Always register both `Responses` and `Activity` on the Managed Deployment when the agent will be reached via Bot Service / Teams.
- Author `agent.metadata` defensively: keep ≤ 8 top-level keys to leave headroom for any future bridge additions.
- Don't stuff per-call tracing/correlation IDs into `metadata`. Use the `ms-cv` HTTP header or OTel `traceparent` instead.
- Move static labels (environment, owner, costCenter) onto ARM tags of the account/project, not onto every Responses call.

## Scripts in this folder

| Script | Purpose |
|---|---|
| [`Get-AgentMetadataAudit.ps1`](./Get-AgentMetadataAudit.ps1) | Counts metadata keys at every Layer-2 location (agent root, tools, workflow steps). Run first to confirm whether the author is contributing. |
| [`Get-ApplicationDeployment.ps1`](./Get-ApplicationDeployment.ps1) | ARM GET on the Agent Application + Managed Deployment. Shows which protocols are registered — this is where you confirm the root cause. |
| [`Patch-DeploymentProtocols.ps1`](./Patch-DeploymentProtocols.ps1) | Idempotent PUT that re-registers the deployment with both `Responses` and `Activity` protocols. Preserves existing `agents[]`, `displayName`, `deploymentType`. |
| [`Get-FailingTraceFromAppInsights.ps1`](./Get-FailingTraceFromAppInsights.ps1) | Pulls failing turns from App Insights by `ms-cv` correlation header. Only useful if the Bot Service's `developerAppInsightsApplicationId` is set. |
| [`Set-AgentMetadata.ps1`](./Set-AgentMetadata.ps1) | Optional remediation if Layer 2 is the offender. Publishes a new agent version with trimmed metadata. |

## API versions used

- Control-plane (ARM): `2026-01-15-preview`
- Data-plane (Foundry data plane): `v1`

## Related repo references

- Bicep module that does the right thing: [`teams-agent-publish-script.bicep`](../../modules-network-secured/teams-agent-publish-script.bicep)
- Teams publish flow: [`PUBLISH.md`](../../PUBLISH.md)
- Teams debugging KQL: [`teams-app-kql-queries.md`](../teams-app-kql-queries.md)
