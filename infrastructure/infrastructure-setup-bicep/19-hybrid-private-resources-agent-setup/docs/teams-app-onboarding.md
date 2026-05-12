# Onboarding the Teams App for the published Foundry agent

This guide picks up **after** infrastructure is provisioned and a TLS cert is in place. It walks through the manual steps to:

1. Build a Teams app package that points at your Bot Service.
2. Sideload or publish it via the Microsoft 365 Teams Admin Center.
3. Drive admin approval through the Microsoft 365 Admin Center.
4. Verify end-to-end (Teams user → Foundry agent).

> Prerequisites:
> - You completed Phases 1-3 of [`PUBLISH.md`](../PUBLISH.md) (`azd provision` succeeded; App Gateway, APIM bot-messaging API, Bot Service + Teams Channel exist; Bot Service `msaAppId` matches the Foundry Agent Application's `defaultInstanceIdentity.clientId`).
> - The TLS cert chain on `https://<customDomain>/bot` validates from the public internet (CA-issued — not self-signed). Self-signed certs work for control-plane provisioning but Bot Channel Adapters will reject them.
> - You're on the M365 tenant that hosts the Foundry account, signed in with an account that can sideload Teams apps. Org-wide distribution additionally needs an M365 admin.

---

## Step 1 — Update the Teams manifest

The repo ships a starter manifest at [`../teams-app/manifest.json`](../teams-app/manifest.json) plus two placeholder icons (`color.png`, `outline.png`). You need to update three things:

1. **`id`** — the unique Teams app id. Must match `botId`. Use the same value as the Bot Service's `msaAppId` (the Foundry Agent Application's `defaultInstanceIdentity.clientId`).
2. **`bots[0].botId`** — same value as `id`.
3. **`developer.*`** — your org's name and URLs. M365 admin policies often reject manifests where these point at obvious placeholders.

Retrieve the bot client id:

```bash
# This is your Bot Service msaAppId (same as the Foundry App clientId)
az resource show -g <rg> --resource-type Microsoft.BotService/botServices \
  -n <applicationName>-bot \
  --query "properties.msaAppId" -o tsv
```

Edit `teams-app/manifest.json` accordingly. Example diff against the stock manifest:

```diff
-  "id": "fbd5861e-effa-4409-ab74-4109b5b12179",
+  "id": "<your-bot-client-id>",
   ...
-      "botId": "fbd5861e-effa-4409-ab74-4109b5b12179"
+      "botId": "<your-bot-client-id>"
```

### Manifest field guidance

| Field | Recommended value |
|---|---|
| `manifestVersion` | `1.17` (current) |
| `version` | semver `MAJOR.MINOR.PATCH`. Increment when republishing. M365 admin diffs by `version`. |
| `name.short` | ≤ 30 chars, displayed in Teams chat header |
| `name.full` | ≤ 100 chars, displayed in the app card |
| `description.short` | One sentence, ≤ 80 chars |
| `description.full` | Longer, ≤ 4000 chars, supports Markdown |
| `developer.name` | ≤ 32 chars (M365 admin rejects longer) |
| `developer.websiteUrl` / `privacyUrl` / `termsOfUseUrl` | All must be HTTPS and reachable |
| `bots[].scopes` | `personal` (1:1 chat), `team` (channels), `groupChat` (group DMs). Keep all three unless you have a specific reason to exclude one. |
| `accentColor` | Hex color used in the agent store card border |
| `icons.color` | 192×192 PNG, full color |
| `icons.outline` | 32×32 PNG, monochrome with transparency |

### Replace placeholder icons

The icons in `teams-app/color.png` and `teams-app/outline.png` are tiny placeholders. Replace with real PNGs that meet:
- `color.png` — 192×192, PNG with full color, can have transparency.
- `outline.png` — 32×32, PNG, **monochrome** white on transparent background. Teams renders this in the sidebar and won't accept colored outline icons.

If you don't yet have branded icons, use any 192×192 / 32×32 placeholders — admin approval may still flag them, but sideloading will succeed.

---

## Step 2 — Build the Teams app package

The package is just a ZIP containing `manifest.json` + the two icons at the root (no subfolders).

### Option A — from a regular terminal

```bash
cd teams-app
# Remove any old build artefact
rm -f marketing-pipeline-teams.zip
# Build the package (manifest.json must be at the zip root, no folder)
zip -j marketing-pipeline-teams.zip manifest.json color.png outline.png
unzip -l marketing-pipeline-teams.zip   # confirm root-level entries
```

### Option B — from PowerShell

```powershell
Set-Location teams-app
Remove-Item marketing-pipeline-teams.zip -ErrorAction SilentlyContinue
Compress-Archive -Path manifest.json, color.png, outline.png `
                 -DestinationPath marketing-pipeline-teams.zip -Force
# Verify
[System.IO.Compression.ZipFile]::OpenRead("$pwd\marketing-pipeline-teams.zip").Entries | Select-Object FullName
```

You should see exactly three entries, all at the root: `manifest.json`, `color.png`, `outline.png`. No folder prefix.

### Validate the manifest before uploading (optional but saves time)

Install the [Teams App Validator](https://learn.microsoft.com/microsoftteams/platform/concepts/deploy-and-publish/appsource/prepare/submission-checklist#5-validate-your-manifest-and-package) or use the **Developer Portal for Teams** (https://dev.teams.microsoft.com) → **Apps** → **Import an existing app**. The portal flags missing icons, malformed URLs, and disallowed names immediately.

---

## Step 3 — Onboard the app

Pick ONE of the three onboarding paths below. They have different audiences and approval requirements.

### Step 3A — Sideload for yourself (testing)

Fastest path. No admin needed. Only you see the bot.

1. Open **Microsoft Teams** (desktop or web).
2. Click **Apps** in the left rail → **Manage your apps** (bottom) → **Upload an app**.
3. Choose **Upload a custom app**.
4. Pick `teams-app/marketing-pipeline-teams.zip`.
5. **Add** the app and start chatting in 1:1 mode.

> If the **Upload a custom app** option is missing, your tenant has [custom-app uploads disabled](https://learn.microsoft.com/microsoftteams/platform/concepts/build-and-test/prepare-your-o365-tenant#enable-custom-teams-apps-and-turn-on-custom-app-uploading). An M365 admin must enable it in the Teams Admin Center (Manage apps → Org-wide app settings → "Upload custom apps").

### Step 3B — Submit to your org (admin approval required)

This is the production path for **organisation-scope** publishing.

1. In Teams, **Apps** → **Manage your apps** → **Upload an app** → **Submit an app to your org**.
2. Pick `marketing-pipeline-teams.zip`.
3. The app shows under **Pending approval** for you, and admins are notified.
4. An M365 admin completes Step 4 below.

Alternatively, the admin can upload directly:
1. M365 admin signs in to the [Teams Admin Center](https://admin.teams.microsoft.com).
2. **Teams apps** → **Manage apps** → **+ Upload new app**.
3. Pick `marketing-pipeline-teams.zip`.
4. The app appears in the org catalog (still subject to app permission policies — see [Step 5](#step-5---make-it-discoverable-organisation-scope)).

### Step 3C — Publish via the Foundry portal (combined IaC + Teams package)

If you used `azd` to provision the Teams stack via this template, the Foundry portal can drive the whole onboarding for you (the portal calls the same APIs as steps 3A/3B but bundles the M365 approval request):

1. https://ai.azure.com → your project → **Agents** → select `marketing-pipeline`.
2. **Publish** → **Publish to Teams and Microsoft 365 Copilot**.
3. The existing Bot Service is detected (read-only).
4. Fill metadata; pick **People in your organization** scope.
5. **Publish**.

This is the recommended path because the Foundry portal also publishes the agent into the M365 Copilot agent store, not just Teams chat. See the [Learn doc](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/publish-copilot) for screenshots.

---

## Step 4 — M365 admin approval (only for Step 3B / 3C with org scope)

1. M365 admin signs in to https://admin.cloud.microsoft/#/agents/all/requested.
2. Locate the pending request (label matches `manifest.json` `name.full`).
3. Review:
   - Bot endpoint matches your App Gateway public domain.
   - `developer.*` URLs are real.
   - Cert chain on the endpoint validates (open the URL in a private browser window — should show a padlock).
4. Click **Approve**.
5. Approval can take 5-15 minutes to fan out. The agent then appears in the **Built by your org** section of the M365 Copilot agent store and is discoverable in Teams.

If approval is rejected, common reasons:
- Cert chain invalid (self-signed) — see [`PUBLISH.md` Cert rotation](../PUBLISH.md#cert-rotation).
- Developer URLs return 404 or are non-HTTPS.
- App name conflicts with an existing one in the tenant.
- nip.io / temporary domain flagged as low-reputation.

---

## Step 5 — Make it discoverable (organisation scope)

Even after admin approval, app **permission policies** can hide the agent from certain user groups. To make it visible to everyone:

1. Teams Admin Center → **Teams apps** → **Permission policies** → check the default policy (or the policies targeted at your user groups).
2. Confirm **Microsoft apps**, **Third-party apps**, and especially **Custom apps** are set to **Allow all apps** (or your custom allow-list includes this app id).
3. If you have a custom **App setup policy** pinning a fixed set of apps to the Teams sidebar, optionally pin this agent to make it more discoverable.

---

## Step 6 — Verify end-to-end

A successful onboarding looks like this. Test in order; if a step fails, the diagnosis is in the layer above.

### 6.1 — Network reachability

```bash
# The cert chain should be valid and Issuer should be Let's Encrypt or a commercial CA
openssl s_client -connect <App Gateway PIP>:443 -servername <customDomain> </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

Expected: `Verify return code: 0 (ok)`, subject CN matches your `customDomain`, issuer is **NOT** the same as subject (would indicate self-signed).

### 6.2 — APIM JWT validation

```bash
# Unauthenticated POST → expect 401 (means the JWT validate-jwt policy is active)
curl -X POST https://<customDomain>/bot \
  -H "Content-Type: application/json" \
  -d '{"type":"message","text":"test"}' -s -o /dev/null -w "%{http_code}\n"
```

Expected: `401`. If you get `200`, JWT validation is bypassed and the bot is open — a security issue, not a functional one (Teams still works, but anyone can call your bot).

### 6.3 — Bot Channel Adapter health

```bash
# Azure Bot Service does a synthetic check every few minutes. View results:
az resource show -g <rg> --resource-type Microsoft.BotService/botServices \
  -n <applicationName>-bot \
  --query "{endpoint:properties.endpoint, validationStatus:properties.endpointValidationStatus}" -o table
```

Expected: `endpointValidationStatus = Succeeded` (or no field if your subscription does not surface it — in that case use the next test).

### 6.4 — End-to-end chat

1. Open Teams. Find the agent under **Apps** → **Built for your org** (after approval) or **Manage your apps** (after sideload).
2. Start a 1:1 chat. Send: `Describe my new AI-powered smart water bottle that tracks hydration and reminds you to drink.`
3. Expected: the agent replies with the polished output of the 3-step workflow (Analyst → Copywriter → Editor).

If the bot is in chat but doesn't reply:
- Open the Bot Service in Azure Portal → **Test in Web Chat** → send a message there. If Web Chat works but Teams doesn't, the Teams Channel needs reconnection (delete and re-add the channel in Azure Bot Service).
- If Web Chat also fails, the path Bot Service → App Gateway → APIM → Foundry is broken. See [`PUBLISH.md` Troubleshooting](../PUBLISH.md#troubleshooting).

---

## Updating a published Teams app

When you change the agent (new version, new instructions, new tools), you usually do **not** need to republish the Teams app. The Bot Service messaging endpoint stays the same — Teams calls the same URL, and the underlying Foundry Agent Application routes to whatever version of the agent is currently active.

You DO need to republish the Teams app when:
- The bot's display name / description / icons changed (metadata visible to users).
- You changed the `botId` (very rare; would mean recreating the Bot Service).
- You added new bot scopes (`personal` → `personal, team, groupChat`) or commands.

To republish:

1. Increment `manifest.json` `version` (e.g. `1.0.0` → `1.0.1`).
2. Rebuild the ZIP.
3. **Teams Admin Center → Manage apps**, find your app, **Update**.
4. Re-approve in the M365 admin center if the change is material (display name / icons / permissions).

---

## Removing a published app

1. **Teams Admin Center** → **Manage apps** → find the app → **Block** (hides immediately) or **Delete** (irreversible).
2. **M365 admin center** → revoke any standing approval at https://admin.cloud.microsoft/#/agents.
3. (Optional) Delete the underlying Bot Service / App Gateway by re-running `azd provision` with `DEPLOY_TEAMS_PUBLISHING=false`, or `azd down` to remove the entire deployment.

---

## Related

- [`PUBLISH.md`](../PUBLISH.md) — full provisioning runbook (Phases 1-3).
- [`docs/teams-app-debugging.md`](teams-app-debugging.md) — diagnostic-logging setup and layer-by-layer fault isolation.
- [Microsoft Foundry — Publish agents to M365 and Teams](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/publish-copilot)
- [Teams app manifest reference (v1.17)](https://learn.microsoft.com/microsoftteams/platform/resources/schema/manifest-schema)
- [Teams Admin Center — Manage apps](https://admin.teams.microsoft.com/policies/manage-apps)
- [M365 admin center — Agent approval queue](https://admin.cloud.microsoft/#/agents/all/requested)
