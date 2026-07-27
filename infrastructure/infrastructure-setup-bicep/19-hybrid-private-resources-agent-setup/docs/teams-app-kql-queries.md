# Kusto (KQL) queries for debugging Teams ↔ Foundry agent

Copy-paste-ready KQL queries against the **Log Analytics workspace** deployed by this template. All queries assume:

- `deployDiagnosticSettings=true` (default) — wires App Gateway, APIM, Bot Service, and Foundry account to `<accountName>appinsights-law`.
- The workspace is set as `logAnalyticsDestinationType: 'Dedicated'`, so resource-specific tables are populated (e.g. `AGWAccessLogs`). Many queries also include a `AzureDiagnostics` fallback for clusters where Dedicated mode hasn't propagated yet.

Run these from:
- The Log Analytics workspace blade in Azure Portal → **Logs**, OR
- `az monitor log-analytics query --workspace <customerId> --analytics-query "<query>" -o table`

Replace `<applicationName>`, `<accountName>`, `<bot-client-id>`, etc., with your values.

---

## 0. Quick health dashboard (paste these into a workbook)

### 0.1 — Is anything broken in the last hour?

```kql
let window = 1h;
union
(
    AGWAccessLogs
    | where TimeGenerated > ago(window) and RequestUri startswith "/bot"
    | summarize Errors = countif(HttpStatus >= 400 and HttpStatus != 401),
                Total = count() by bin(TimeGenerated, 5m)
    | extend Layer = "AppGateway"
),
(
    ApiManagementGatewayLogs
    | where TimeGenerated > ago(window) and ApiId == "bot-messaging"
    | summarize Errors = countif(ResponseCode >= 400 and ResponseCode != 401),
                Total = count() by bin(TimeGenerated, 5m)
    | extend Layer = "APIM"
),
(
    ABSBotRequest
    | where TimeGenerated > ago(window)
    | summarize Errors = countif(ResultType != "Success"),
                Total = count() by bin(TimeGenerated, 5m)
    | extend Layer = "BotService"
)
| order by TimeGenerated desc, Layer asc
```

> If any `Errors > 0` row appears, drill into that layer's dedicated section below.

### 0.2 — End-to-end request rate

```kql
AGWAccessLogs
| where TimeGenerated > ago(24h) and RequestUri startswith "/bot"
| summarize Requests = count(), Errors = countif(HttpStatus >= 400)
            by bin(TimeGenerated, 30m), HttpStatus
| render timechart
```

### 0.3 — Latency percentiles by layer

```kql
union
(
    AGWAccessLogs
    | where TimeGenerated > ago(24h) and RequestUri startswith "/bot"
    | summarize p50_ms = percentile(TimeTaken, 50),
                p95_ms = percentile(TimeTaken, 95),
                p99_ms = percentile(TimeTaken, 99)
    | extend Layer = "AppGateway → APIM (total)"
),
(
    ApiManagementGatewayLogs
    | where TimeGenerated > ago(24h) and ApiId == "bot-messaging"
    | summarize p50_ms = percentile(TotalTime, 50),
                p95_ms = percentile(TotalTime, 95),
                p99_ms = percentile(TotalTime, 99)
    | extend Layer = "APIM → Foundry"
),
(
    AppDependencies
    | where TimeGenerated > ago(24h) and (Name contains "invoke_agent" or Name contains "/protocols/activityprotocol")
    | summarize p50_ms = percentile(DurationMs, 50),
                p95_ms = percentile(DurationMs, 95),
                p99_ms = percentile(DurationMs, 99)
    | extend Layer = "Foundry agent (model + tools)"
)
| project Layer, p50_ms, p95_ms, p99_ms
```

---

## 1. Application Gateway

Logs go to:
- `AGWAccessLogs` (dedicated mode — preferred), or
- `AzureDiagnostics | where ResourceType == "APPLICATIONGATEWAYS" and Category == "ApplicationGatewayAccessLog"` (legacy mode fallback)

### 1.1 — Recent /bot requests with backend health

```kql
AGWAccessLogs
| where TimeGenerated > ago(1h) and RequestUri startswith "/bot"
| project TimeGenerated, ClientIp, HttpMethod, RequestUri,
          HttpStatus, ServerStatus, BackendPoolName, ServerRouted,
          TimeTaken_ms = TimeTaken,
          ServerLatency_ms = ServerResponseLatency,
          SslProtocol, SslCipher, ErrorInfo
| order by TimeGenerated desc
| take 50
```

**Reading the columns:**
- `HttpStatus` is what the App Gateway returned to the client.
- `ServerStatus` is what the backend (APIM) returned. `HttpStatus = 502` + `ServerStatus = 0` means the App Gateway never got a response from APIM.
- `ErrorInfo` populates on failure with one of: `ERRORINFO_NO_ERROR`, `ERRORINFO_TIMEOUT`, `ERRORINFO_CONNECTION_RESET`, `ERRORINFO_TLS_HANDSHAKE_TIMEOUT`, etc.
- `ServerRouted` shows which backend address was selected (the APIM private IP).

### 1.2 — 5xx errors with reason

```kql
AGWAccessLogs
| where TimeGenerated > ago(1h) and HttpStatus >= 500
| summarize Count = count() by HttpStatus, ServerStatus, ErrorInfo, BackendPoolName
| order by Count desc
```

### 1.3 — WAF blocks (when getting 403)

```kql
AGWFirewallLogs
| where TimeGenerated > ago(1h) and Action == "Blocked"
| project TimeGenerated, RuleId, Message, TransactionId, RequestUri, Hostname, ClientIp, Details
| order by TimeGenerated desc
| take 50
```

**Common false positives on bot traffic:**
- `942100` — SQL injection regex matched on a normal JSON body
- `949110` — anomaly score threshold reached due to multiple low-severity rule hits

For these, add a per-rule exclusion in the WAF policy (NOT a global mode change).

### 1.4 — Backend health probe timeline

```kql
AGWPerformanceLogs
| where TimeGenerated > ago(2h)
| project TimeGenerated, InstanceId, HealthyHostCount, UnhealthyHostCount, BackendPoolName = backendPoolName_s
| order by TimeGenerated desc
```

If `UnhealthyHostCount > 0` persistently, the probe configuration is wrong or APIM is unreachable.

### 1.5 — TLS handshake failures (cert / SNI issues)

```kql
AGWAccessLogs
| where TimeGenerated > ago(1h) and ErrorInfo has "TLS"
| summarize Count = count() by ErrorInfo, SslProtocol, SslCipher
```

### 1.6 — Legacy AzureDiagnostics version of 1.1 (if Dedicated mode hasn't propagated yet)

```kql
AzureDiagnostics
| where TimeGenerated > ago(1h)
| where ResourceType == "APPLICATIONGATEWAYS" and Category == "ApplicationGatewayAccessLog"
| where requestUri_s startswith "/bot"
| project TimeGenerated, clientIP_s, httpMethod_s, requestUri_s,
          httpStatus_d, host_s, backendIPAddress_s,
          TimeTaken_ms = timeTaken_d,
          ServerLatency_ms = serverResponseLatency_s,
          sslEnabled_s, sslCipher_s
| order by TimeGenerated desc
| take 50
```

---

## 2. API Management — `bot-messaging` API

Logs go to:
- `ApiManagementGatewayLogs` (dedicated mode), or
- `AzureDiagnostics | where ResourceType == "SERVICE" and Category == "GatewayLogs"` (legacy)

### 2.1 — Recent bot-messaging requests with backend (Foundry) response

```kql
ApiManagementGatewayLogs
| where TimeGenerated > ago(1h) and ApiId == "bot-messaging"
| project TimeGenerated, Method, Url, ResponseCode, BackendResponseCode,
          TotalTime_ms = TotalTime, BackendTime_ms = BackendTime,
          OperationId, CorrelationId, ErrorReason, IsRequestSuccess,
          ClientIp = ClientIP, ClientProtocol
| order by TimeGenerated desc
| take 50
```

**Decoding the codes:**

| `ResponseCode` | `BackendResponseCode` | Meaning |
|---|---|---|
| `401` | (empty / 0) | JWT validation failed — APIM never called Foundry |
| `200` | `200` | End-to-end success |
| `500` | (empty / 0) | APIM policy error — syntax or named-value resolution |
| `502` | (empty / 0) | Foundry endpoint unreachable from APIM |
| `200` | `400` | Foundry rejected the call — most likely missing `api-version` in rewrite-uri |
| `200` | `404` | Foundry path wrong — `serviceUrl` doesn't end with `/protocols/activityprotocol` |
| `429` | any | APIM rate limit hit |

### 2.2 — JWT validation failures with reason

```kql
ApiManagementGatewayLogs
| where TimeGenerated > ago(1h) and ApiId == "bot-messaging" and ResponseCode == 401
| project TimeGenerated, OperationId, ErrorReason, RequestHeaders = tostring(RequestHeaders), ClientIP
| extend AuthHeader = extract(@"Authorization: Bearer (.+?)(?:\s|$)", 1, RequestHeaders)
| project TimeGenerated, OperationId, ErrorReason, AuthHeaderPrefix = substring(AuthHeader, 0, 40), ClientIP
| order by TimeGenerated desc
| take 50
```

`ErrorReason` typically reads `JWT Validation Failed: Lifetime validation failed. The token is expired.` or `JWT Validation Failed: IDX10503: Signature validation failed.` or `Audience claim invalid`.

### 2.3 — Foundry backend latency outliers

```kql
ApiManagementGatewayLogs
| where TimeGenerated > ago(6h) and ApiId == "bot-messaging" and ResponseCode == 200
| summarize p50 = percentile(BackendTime, 50),
            p95 = percentile(BackendTime, 95),
            p99 = percentile(BackendTime, 99),
            max_ms = max(BackendTime),
            calls = count()
            by bin(TimeGenerated, 15m)
| order by TimeGenerated desc
```

### 2.4 — All errors (any code) grouped by reason

```kql
ApiManagementGatewayLogs
| where TimeGenerated > ago(24h) and ApiId == "bot-messaging" and IsRequestSuccess == false
| summarize Count = count() by ResponseCode, BackendResponseCode, ErrorReason
| order by Count desc
```

### 2.5 — Per-API call trace (APIM App Insights tracing — sampled at 100% by this template)

Available because `deployDiagnosticSettings=true` wires the App Insights logger on the bot-messaging API.

```kql
AppRequests
| where TimeGenerated > ago(1h) and Name has "bot-messaging"
| project TimeGenerated, Name, Url, ResultCode, DurationMs, OperationId, Success
| order by TimeGenerated desc
| take 50
```

Then drill into a specific request's full trace:

```kql
let opId = "<operationId-from-above>";
union AppRequests, AppDependencies, AppTraces
| where TimeGenerated > ago(2h) and OperationId == opId
| project TimeGenerated, ItemType, Name, ResultCode, DurationMs, Message, OperationName, Properties
| order by TimeGenerated asc
```

---

## 3. Azure Bot Service

Logs go to one of two tables depending on the `logAnalyticsDestinationType` on the diagnostic setting:

- **`ABSBotRequest`** (dedicated mode — preferred, used by this template's Bicep). Created on first write; will be empty until real Bot Channel traffic arrives.
- **`AzureDiagnostics | where ResourceType == "BOTSERVICES"`** (legacy mode fallback).

### 3.1 — Recent channel adapter requests (dedicated)

```kql
ABSBotRequest
| where TimeGenerated > ago(1h)
| project TimeGenerated, OperationName, ResultType, ResultDescription,
          DurationMs, ChannelId, ActivityType,
          BotName = _ResourceId, CallerAppId, Url,
          AuthorizationStatus, StatusCode, CorrelationId, ActivityId
| order by TimeGenerated desc
| take 50
```

**Reading the columns:**
- `OperationName` is the Bot Framework operation: `SendActivity` (user → bot, the main one), `ReplyToActivity` (bot → user), `CreateConversation`, `UpdateActivity`, `DeleteActivity`, `GetUserToken`, `SignOutUser`, etc.
- `ResultType` is `Success` or `ClientError` / `ServerError`.
- `StatusCode` is the HTTP status returned **by your bot endpoint** to the Bot Channel Adapter. `200` means your endpoint accepted the activity; `4xx`/`5xx` means it refused.
- `ChannelId` — `msteams`, `webchat`, `directline`, `slack`, `emulator`, etc. For Teams chats this is `msteams`.
- `ActivityType` — `message`, `conversationUpdate`, `typing`, `event`, `invoke`. Most user traffic is `message`; `conversationUpdate` fires when a user adds/removes the bot from a chat.
- `AuthorizationStatus` — `success` or `failed`. `failed` here means the bot endpoint rejected the Channel Adapter's JWT (APIM `validate-jwt` policy declined it).
- `CallerAppId` — the Bot Channel Adapter's app id (a Microsoft-internal id) when the call comes from Teams/Web Chat. Different from your bot's `msaAppId`.

### 3.2 — Failed bot requests grouped by reason (dedicated)

```kql
ABSBotRequest
| where TimeGenerated > ago(6h) and ResultType != "Success"
| summarize Count = count() by ResultType, ResultDescription, OperationName,
            ChannelId, StatusCode, AuthorizationStatus
| order by Count desc
```

**Common combinations and what they mean:**

| ResultType | StatusCode | AuthorizationStatus | Diagnosis |
|---|---|---|---|
| `ServerError` | `0` (no response) | (any) | Bot endpoint unreachable from Channel Adapter — TLS chain rejected, DNS failed, or App Gateway is down. Test public TLS with `openssl s_client`. |
| `ServerError` | `502` / `503` | (any) | App Gateway returned 5xx (APIM unhealthy). Drill into [§1.2](#12--5xx-errors-with-reason). |
| `ServerError` | `504` | (any) | Backend timeout (Foundry agent took too long to respond, default Bot Channel timeout is 15s). |
| `ClientError` | `401` | `failed` | APIM JWT validation rejected the Channel Adapter token. Audience mismatch — verify Bot Service `msaAppId` equals the value in the APIM `validate-jwt` audiences. |
| `ClientError` | `403` | `failed` | Channel Adapter's token was valid but the bot refused it for another policy reason. |
| `ClientError` | `404` | (success or n/a) | Endpoint URL mismatch — Bot Service `endpoint` points at a path APIM doesn't expose. |

### 3.3 — Channel-specific failure rate (dedicated)

```kql
ABSBotRequest
| where TimeGenerated > ago(24h)
| summarize Total = count(),
            Failed = countif(ResultType != "Success")
            by ChannelId
| extend FailRate_pct = round(100.0 * Failed / Total, 2)
| order by Total desc
```

If `msteams` shows high `FailRate_pct` but `webchat` is clean, the issue is specific to Teams Channel binding (re-add the channel in the Bot Service Channels blade).

### 3.4 — Live timeline of one specific conversation

When you're debugging a specific Teams chat, get its conversation/activity ids and trace the full sequence:

```kql
// Get all activities in the last 15 min from a channel
ABSBotRequest
| where TimeGenerated > ago(15m) and ChannelId == "msteams"
| project TimeGenerated, ActivityType, OperationName, ResultType,
          StatusCode, DurationMs, ActivityId, CorrelationId, BotName = _ResourceId
| order by TimeGenerated asc
```

Then pick a `CorrelationId` and pull every record for it:

```kql
let cid = "<correlation-id-from-above>";
ABSBotRequest
| where TimeGenerated > ago(30m) and CorrelationId == cid
| project TimeGenerated, OperationName, ActivityType, ResultType,
          StatusCode, DurationMs, ResultDescription, Url
| order by TimeGenerated asc
```

A normal Teams message exchange shows two records under the same `CorrelationId`:
1. `SendActivity` — user message arrives at bot
2. `ReplyToActivity` — bot's response goes back

If you see #1 with `Success` but no #2, the bot processed the message but never replied (likely a Foundry agent failure — drill into §4 and §5).

### 3.5 — Authentication / authorization failures specifically

```kql
ABSBotRequest
| where TimeGenerated > ago(6h) and AuthorizationStatus == "failed"
| summarize Count = count() by ResultDescription, CallerAppId, StatusCode
| order by Count desc
```

If `Count` is non-zero with `StatusCode == 401`, this confirms APIM's `validate-jwt` is the gate that's failing. Cross-reference with [§2.2](#22--jwt-validation-failures-with-reason) — both queries should show the same time-aligned spike.

### 3.6 — Latency from Bot Channel Adapter's perspective

```kql
ABSBotRequest
| where TimeGenerated > ago(24h) and ResultType == "Success"
            and OperationName == "SendActivity"
| summarize p50_ms = percentile(DurationMs, 50),
            p95_ms = percentile(DurationMs, 95),
            p99_ms = percentile(DurationMs, 99),
            max_ms = max(DurationMs),
            calls = count()
            by ChannelId, bin(TimeGenerated, 15m)
| order by TimeGenerated desc
```

This is end-to-end "how long did the bot take from the Channel Adapter's wallclock perspective" — includes the round-trip through App Gateway, APIM, and Foundry. Compare against [§0.3](#03--latency-percentiles-by-layer) to identify the slow layer.

### 3.7 — Conversation update events (user added/removed the bot)

Useful to confirm bot was successfully added to a chat/team:

```kql
ABSBotRequest
| where TimeGenerated > ago(7d) and ActivityType == "conversationUpdate"
| project TimeGenerated, ChannelId, OperationName, ResultType, BotName = _ResourceId
| order by TimeGenerated desc
| take 100
```

### 3.8 — Legacy AzureDiagnostics version (fallback if ABSBotRequest is empty)

```kql
AzureDiagnostics
| where TimeGenerated > ago(1h)
| where ResourceType == "BOTSERVICES" and Category == "BotRequest"
| project TimeGenerated, OperationName, ResultType, DurationMs,
          Channel = channel_s,
          Activity = activityType_s,
          BotName = bot_s,
          ResultDescription,
          StatusCode = httpStatus_d,
          AuthStatus = authorizationStatus_s,
          CorrelationId
| order by TimeGenerated desc
| take 50
```

If both `ABSBotRequest` AND `AzureDiagnostics ResourceType=="BOTSERVICES"` are empty, then no Channel Adapter traffic has reached the Bot Service at all — the issue is upstream (Channel binding, DNS, or Teams Admin Center hasn't propagated the app yet).

---

## 4. Foundry account / Cognitive Services data plane

Logs go to:
- `AzureDiagnostics | where ResourceType == "ACCOUNTS" and ResourceProvider == "MICROSOFT.COGNITIVESERVICES"`
- Or resource-specific tables `AOAIRequestResponseLogs` (Azure OpenAI), `AOAIAuditLogs`, etc. (dedicated mode)

### 4.1 — Activity Protocol calls reaching Foundry

```kql
AzureDiagnostics
| where TimeGenerated > ago(1h)
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES" and ResourceType == "ACCOUNTS"
| where Category == "RequestResponse"
| where requestUri_s contains "/protocols/activityprotocol"
| project TimeGenerated, OperationName, ResultType, DurationMs,
          requestUri_s, properties_s, identity_s,
          clientIP_s = CallerIpAddress
| order by TimeGenerated desc
| take 50
```

### 4.2 — Model calls (Foundry → Azure OpenAI)

```kql
AzureDiagnostics
| where TimeGenerated > ago(1h)
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where Category in ("RequestResponse", "AOAIRequestResponse")
| where requestUri_s contains "/chat/completions" or requestUri_s contains "/responses"
| extend Model = extract(@"deployments/([^/]+)/", 1, requestUri_s)
| project TimeGenerated, ResultType, DurationMs, Model,
          PromptTokens = todouble(properties_s.promptTokens),
          CompletionTokens = todouble(properties_s.completionTokens),
          requestUri_s
| order by TimeGenerated desc
| take 50
```

### 4.3 — 429 throttling rate by model

```kql
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where ResultType == "TooManyRequests" or httpStatusCode_d == 429
| extend Model = extract(@"deployments/([^/]+)/", 1, requestUri_s)
| summarize Count = count() by Model, bin(TimeGenerated, 15m)
| render timechart
```

If you see 429s here, increase the model deployment's `sku.capacity` or move to a higher TPM tier.

---

## 5. Application Insights — agent traces

The Foundry project's Application Insights instrumentation populates `AppRequests`, `AppDependencies`, `AppTraces`, and `AppExceptions`.

### 5.1 — Workflow agent invocations

```kql
AppDependencies
| where TimeGenerated > ago(1h)
| where Name contains "invoke_agent" or Name contains "workflow"
| project TimeGenerated, Name, Target, DurationMs, ResultCode, Success,
          OperationName, OperationId
| order by TimeGenerated desc
| take 50
```

### 5.2 — Per-step latency inside the workflow

For the marketing-pipeline workflow specifically:

```kql
AppDependencies
| where TimeGenerated > ago(2h)
| where Name in ("invoke_agent.marketing-analyst", "invoke_agent.marketing-copywriter", "invoke_agent.marketing-editor")
| summarize p50_ms = percentile(DurationMs, 50),
            p95_ms = percentile(DurationMs, 95),
            calls = count(),
            failures = countif(Success == false)
            by Step = Name
| order by Step asc
```

### 5.3 — Tool invocations (AI Search, MCP, etc.)

```kql
AppDependencies
| where TimeGenerated > ago(1h) and Name has "tool"
| project TimeGenerated, Name, Target, DurationMs, ResultCode, Success
| order by TimeGenerated desc
| take 50
```

### 5.4 — Recent exceptions

```kql
AppExceptions
| where TimeGenerated > ago(6h)
| project TimeGenerated, ProblemId, Type, OuterMessage, Method, AppRoleName, OperationId
| order by TimeGenerated desc
| take 50
```

### 5.5 — APIM trace breakdown for a slow request (after MANUAL STEP 0 wires APIM Application Insights)

Get the slowest 5 requests:

```kql
AppRequests
| where TimeGenerated > ago(1h) and Name has "bot-messaging"
| top 5 by DurationMs desc
| project TimeGenerated, OperationId, DurationMs, ResultCode
```

Then full trace for one of them:

```kql
let opId = "<operationId-from-above>";
union AppRequests, AppDependencies, AppTraces, AppExceptions
| where TimeGenerated > ago(2h) and OperationId == opId
| project TimeGenerated, ItemType, Name, ResultCode, DurationMs, Message
| order by TimeGenerated asc
```

---

## 6. End-to-end correlation

Bot Service, App Gateway, APIM, and Foundry don't share a single trace id automatically, but you can correlate by **time window + bot client ip**.

### 6.1 — One Teams message, all layers

Pick a message sent in Teams and note the approximate time (within 30 seconds). Then:

```kql
let centerTime = todatetime("2026-05-12T15:30:00Z"); // approx time of your test message
let window = 15s;
union
(
    ABSBotRequest
    | where TimeGenerated between (centerTime - window .. centerTime + window)
    | project TimeGenerated, Layer = "1.Bot", Op = OperationName, Result = ResultType,
              Detail = strcat(ResultDescription, " [", ChannelId, "/", ActivityType, "]"),
              Dur_ms = DurationMs
),
(
    AGWAccessLogs
    | where TimeGenerated between (centerTime - window .. centerTime + window)
    | where RequestUri startswith "/bot"
    | project TimeGenerated, Layer = "2.AGW", Op = HttpMethod, Result = tostring(HttpStatus), Detail = ErrorInfo, Dur_ms = TimeTaken
),
(
    ApiManagementGatewayLogs
    | where TimeGenerated between (centerTime - window .. centerTime + window)
    | where ApiId == "bot-messaging"
    | project TimeGenerated, Layer = "3.APIM", Op = Method, Result = strcat(ResponseCode, "/", BackendResponseCode), Detail = ErrorReason, Dur_ms = TotalTime
),
(
    AzureDiagnostics
    | where TimeGenerated between (centerTime - window .. centerTime + window)
    | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
    | where requestUri_s contains "activityprotocol"
    | project TimeGenerated, Layer = "4.Foundry", Op = OperationName, Result = ResultType, Detail = ResultDescription, Dur_ms = DurationMs
)
| order by TimeGenerated asc
```

You'll see a 4-row sequence showing the same message at each layer. The first layer with a non-success row is where the failure happened.

---

## 7. Saved-query starter pack (recommended to save in your workspace)

| Save as | Query (link to section above) |
|---|---|
| `bot-health-1h` | [§0.1](#01--is-anything-broken-in-the-last-hour) |
| `bot-latency-by-layer` | [§0.3](#03--latency-percentiles-by-layer) |
| `appgw-5xx-now` | [§1.2](#12--5xx-errors-with-reason) |
| `apim-jwt-fails` | [§2.2](#22--jwt-validation-failures-with-reason) |
| `bot-service-failed-channels` | [§3.3](#33--channel-specific-failure-rate-last-24h) |
| `model-throttling` | [§4.3](#43--429-throttling-rate-by-model) |
| `workflow-step-latency` | [§5.2](#52--per-step-latency-inside-the-workflow) |
| `e2e-correlation-window` | [§6.1](#61--one-teams-message-all-layers) |

In the Log Analytics workspace UI: **Logs** → run query → **Save** → **Save as function** or **Save as query** → pick category `bot-debugging`.

---

## 8. Quick recipes

### "I just sent a Teams message and nothing happened"

1. Run [§6.1](#61--one-teams-message-all-layers) with `centerTime` = approx now.
2. First missing layer = failure point.
3. Drill into that layer's section above for the specific symptom.

### "Everything looks fine but users complain it's slow"

1. [§0.3](#03--latency-percentiles-by-layer) — see which layer's p95 is high.
2. App Gateway p95 high → likely WAF processing time (§1.4 + AGWPerformanceLogs).
3. APIM p95 high → backend (Foundry) is slow, see §4.2.
4. Foundry p95 high → model is slow, see §4.3 for throttling or §5.2 for workflow step breakdown.

### "Cert is changing soon, will it cause an outage?"

```kql
AGWAccessLogs
| where TimeGenerated > ago(7d)
| where ErrorInfo has "TLS" or HttpStatus == 525
| summarize Count = count() by bin(TimeGenerated, 1h), ErrorInfo
```

If zero rows for 7 days, cert change in-place is safe (App Gateway hot-reloads from Key Vault on import).

### "Did anyone use the bot today?"

```kql
AGWAccessLogs
| where TimeGenerated > ago(1d) and RequestUri startswith "/bot" and HttpMethod == "POST"
| summarize Requests = count(), Users = dcount(ClientIp)
            by bin(TimeGenerated, 1h)
| render columnchart
```

---

## Notes on diagnostic-table modes

This template configures `logAnalyticsDestinationType: 'Dedicated'`. On a freshly enabled workspace:

- **App Gateway** writes to `AGWAccessLogs`, `AGWFirewallLogs`, `AGWPerformanceLogs`. First-write latency is ~5-15 min after the policy update.
- **APIM** writes to `ApiManagementGatewayLogs` and `ApiManagementWebSocketConnectionLogs`.
- **Bot Service** writes to `ABSBotRequest` (dedicated mode). This is the table referenced throughout §3 above.
- **Cognitive Services / Foundry** may go to dedicated `AOAIRequestResponseLogs` and `AOAIAuditLogs` for Azure OpenAI traffic; project-level traces (Foundry-native) go to `AppRequests`/`AppDependencies` via App Insights.

If a dedicated table is empty but the legacy `AzureDiagnostics` has data, the diag setting was created in legacy mode. Switching is non-destructive — just redeploy with `deployDiagnosticSettings=true` (this template already uses Dedicated mode in the Bicep), and future logs flow to the dedicated table. Old logs stay in `AzureDiagnostics`.

---

## Related

- [`docs/teams-app-debugging.md`](teams-app-debugging.md) — narrative debug guide with diagnostic-setting setup and layer-by-layer fault isolation
- [`docs/teams-app-onboarding.md`](teams-app-onboarding.md) — onboarding runbook
- [`PUBLISH.md`](../PUBLISH.md) — provisioning runbook
- [Azure Monitor — App Gateway diagnostic logs reference](https://learn.microsoft.com/azure/application-gateway/application-gateway-diagnostics)
- [APIM diagnostic logs reference](https://learn.microsoft.com/azure/api-management/api-management-howto-use-azure-monitor)
- [Bot Service diagnostic logs reference](https://learn.microsoft.com/azure/bot-service/bot-service-resources-bot-framework-rest-connector-authentication#troubleshooting)
- [Azure OpenAI / Cognitive Services diagnostic reference](https://learn.microsoft.com/azure/ai-services/openai/how-to/monitor-openai)
