# Publishing Agents to Microsoft Teams

This guide covers publishing Foundry agents to Microsoft Teams while keeping the agent on a private network.

## Architecture

```
Teams User → Microsoft Channel Adapter
  → Application Gateway (WAF v2, TLS termination, custom domain)
  → APIM (JWT validation: issuer=api.botframework.com, audience=Bot Client ID)
  → Foundry Agent Private Endpoint
  → Agent Service → APIM Gateway → LLM
```

**Security controls:**
- ✅ Agent stays on private endpoint (no public access)
- ✅ WAF protection at Application Gateway edge
- ✅ JWT validation at APIM (Microsoft-signed Bot tokens only)
- ✅ JWT audience locked to specific Bot Client ID
- ✅ Source IPs can be restricted to AzureBotService service tag
- ✅ Outbound limited to specific Microsoft FQDNs

See [diagrams/sequence-diagram.md](diagrams/sequence-diagram.md) for the full sequence diagram.

## Prerequisites

1. A **custom DNS domain** you own (e.g., `agent.yourcompany.com`)
2. A **TLS certificate** for that domain (PFX format)
3. APIM deployed (`deployApiManagement=true`)
4. An agent or workflow created and tested
5. `Microsoft.BotService` provider registered:
   ```bash
   az provider register --namespace Microsoft.BotService
   ```

## Step 1: Deploy Infrastructure (IaC)

Deploy with Teams publishing enabled:

```bash
az deployment group create \
  --resource-group "rg-hybrid-agent-test" \
  --template-file main.bicep \
  --parameters \
    deployApiManagement=true \
    deployTeamsPublishing=true \
    teamsCustomDomain="agent.yourcompany.com" \
    teamsAgentName="marketing-pipeline" \
    teamsApplicationName="marketing-pipeline-teams"
```

This creates:
- Application Gateway WAF v2 with public IP
- APIM Bot messaging API with JWT validation
- Azure Bot Service linked to Application Gateway
- Teams Channel on the Bot Service
- Key Vault for TLS certificate
- Agent Application + Managed Deployment (via deployment script)

## Step 2: Upload TLS Certificate

After deployment, upload your TLS certificate to Key Vault:

```bash
# Get the Key Vault name from deployment outputs
KV_NAME=$(az deployment group show \
  --resource-group "rg-hybrid-agent-test" \
  --name "main" \
  --query "properties.outputs.keyVaultName.value" -o tsv)

# Upload PFX certificate
az keyvault certificate import \
  --vault-name "$KV_NAME" \
  --name "teams-bot-tls" \
  --file /path/to/your-certificate.pfx \
  --password "your-pfx-password"
```

## Step 3: Configure DNS

Create a DNS A record pointing your custom domain to the Application Gateway public IP:

```bash
# Get the public IP
APP_GW_IP=$(az deployment group show \
  --resource-group "rg-hybrid-agent-test" \
  --name "main" \
  --query "properties.outputs.appGatewayPublicIp.value" -o tsv)

echo "Create DNS A record: agent.yourcompany.com → $APP_GW_IP"
```

Configure this in your DNS provider:
- **Record Type:** A
- **Host:** `agent` (or your subdomain)
- **Value:** The Application Gateway public IP
- **TTL:** 300 (5 minutes)

## Step 4: Create Teams App Package

Create a `manifest.json` for your Teams app:

```json
{
  "$schema": "https://developer.microsoft.com/en-us/json-schemas/teams/v1.17/MicrosoftTeams.schema.json",
  "manifestVersion": "1.17",
  "version": "1.0.0",
  "id": "<your-bot-client-id>",
  "developer": {
    "name": "Your Organization",
    "websiteUrl": "https://yourcompany.com",
    "privacyUrl": "https://yourcompany.com/privacy",
    "termsOfUseUrl": "https://yourcompany.com/terms"
  },
  "name": {
    "short": "Marketing Pipeline",
    "full": "Marketing Pipeline AI Agent"
  },
  "description": {
    "short": "AI-powered marketing content pipeline",
    "full": "Sequential workflow that analyzes products, writes marketing copy, and polishes the final output using specialized AI agents."
  },
  "icons": {
    "outline": "outline.png",
    "color": "color.png"
  },
  "accentColor": "#0078D4",
  "bots": [
    {
      "botId": "<your-bot-client-id>",
      "scopes": ["personal", "team", "groupChat"],
      "commandLists": [
        {
          "scopes": ["personal"],
          "commands": [
            {
              "title": "Analyze",
              "description": "Describe a product and get marketing copy"
            }
          ]
        }
      ]
    }
  ]
}
```

Replace `<your-bot-client-id>` with the Bot Client ID from the deployment output.

Create icon files (32x32 outline.png, 192x192 color.png) and package:

```bash
# Create the package
zip -j teams-app.zip manifest.json outline.png color.png
```

## Step 5: Upload to Teams

### Individual Scope (Testing)

1. Open **Microsoft Teams**
2. Go to **Apps** → **Manage your apps** → **Upload an app**
3. Select **Upload a custom app**
4. Choose `teams-app.zip`
5. Test the agent in a chat

### Organization Scope (Production)

1. Go to [Teams Admin Center](https://admin.teams.microsoft.com)
2. Navigate to **Teams apps** → **Manage apps**
3. Select **Upload new app**
4. Upload `teams-app.zip`
5. The app appears under **Pending approval**
6. An admin approves it in the [Microsoft 365 Admin Center](https://admin.cloud.microsoft/?#/agents/all/requested)
7. Once approved, the agent appears in the **Built by your org** section

## Step 6: Verify

1. **Test in Teams** — Send a message to the agent and verify it responds
2. **Check Bot Service** — Azure Portal → Bot Service → verify it's running
3. **Check APIM logs** — Verify JWT validation is working (no 401s for valid requests)
4. **Check App Insights** — Verify traces appear for Teams-originated requests

## Troubleshooting

| Issue | Cause | Resolution |
|-------|-------|------------|
| Agent doesn't respond in Teams | Bot endpoint unreachable | Verify DNS A record + App Gateway + APIM connectivity |
| 401 errors in APIM | JWT validation failing | Check Bot Client ID matches in APIM policy |
| Agent responds in Foundry but not Teams | Outbound blocked | Ensure firewall allows outbound to `smba.trafficmanager.net`, `login.microsoftonline.com`, `login.botframework.com` |
| TLS errors | Certificate mismatch | Verify cert in Key Vault matches custom domain |
| Silent failures (messages received, no reply) | Outbound blocked silently | Check firewall logs for dropped connections to `smba.trafficmanager.net` |

## Firewall Rules

If you have a firewall controlling outbound traffic, allow these FQDNs:

| FQDN | Purpose |
|------|---------|
| `smba.trafficmanager.net` | Bot reply endpoint (agent → Teams) |
| `login.microsoftonline.com` | Entra ID token acquisition |
| `login.botframework.com` | Bot Framework OIDC metadata |

For inbound, restrict source IPs to the `AzureBotService` service tag from the [Azure IP Ranges file](https://www.microsoft.com/en-us/download/details.aspx?id=56519).

## Security Reference

| Layer | Control |
|-------|---------|
| **Network perimeter** | WAF v2 on Application Gateway, AzureBotService IP restriction |
| **TLS** | Terminated at App Gateway with your own certificate |
| **Authentication** | Microsoft-signed JWT validated at APIM |
| **Authorization** | JWT audience locked to your Bot Client ID |
| **Agent isolation** | Private endpoint, unreachable from public internet |
| **Outbound** | Limited to specific Microsoft FQDNs |
| **Identity** | Published agent gets its own Entra agent identity |
