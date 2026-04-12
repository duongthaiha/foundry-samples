# Sequence Diagram: Agent Interaction via APIM Gateway

## Flow 1: Published Agent (eastus2 — gpt-4o-mini)

```mermaid
sequenceDiagram
    autonumber
    participant User as 👤 User / Client
    participant App as 📦 Agent Application<br/>(apim-gateway-app)
    participant Agent as 🤖 Agent Service<br/>(apim-gateway-test-agent)
    participant ConnStore as 🔌 Connection Store<br/>(projectcdpy)
    participant PE_APIM as 🔗 Private Endpoint<br/>(pe-subnet)
    participant APIM as 🔀 APIM Gateway<br/>(aiservicescdpyapim)
    participant PE_AI as 🔗 Private Endpoint<br/>(pe-subnet)
    participant LLM as 🧠 AI Services<br/>(aiservicescdpy)
    participant AppIns as 📈 App Insights

    User->>+App: POST /applications/apim-gateway-app<br/>/protocols/openai/responses<br/>Authorization: Bearer (Entra ID)
    App->>App: Validate RBAC<br/>(Azure AI User role)
    App->>+Agent: Route to agent<br/>apim-gateway-test-agent:v2

    Agent->>+ConnStore: Resolve model<br/>"apim-gateway/gpt-4o-mini"
    ConnStore-->>-Agent: Connection: apim-gateway<br/>Target: https://apim.azure-api.net/openai<br/>Auth: ApiKey (subscription key)<br/>Metadata: deploymentInPath=true

    Agent->>+PE_APIM: POST /openai/deployments/gpt-4o-mini<br/>/chat/completions?api-version=2024-10-21<br/>Header: Ocp-Apim-Subscription-Key
    Note over PE_APIM: Private endpoint<br/>192.168.1.x → APIM

    PE_APIM->>+APIM: Forward request<br/>(private link)
    APIM->>APIM: Apply inbound policy:<br/>authentication-managed-identity<br/>resource=cognitiveservices.azure.com
    APIM->>APIM: Acquire Entra token<br/>using System Managed Identity

    APIM->>+PE_AI: POST /openai/deployments/gpt-4o-mini<br/>/chat/completions<br/>Authorization: Bearer (MI token)
    Note over PE_AI: Private endpoint<br/>192.168.1.x → AI Services

    PE_AI->>+LLM: Forward to model<br/>(private link)
    LLM->>LLM: gpt-4o-mini inference
    LLM-->>-PE_AI: Chat completion response

    PE_AI-->>-APIM: Response
    APIM-->>-PE_APIM: Response
    PE_APIM-->>-Agent: Model response

    Agent-->>-App: Agent response
    App-->>-User: Response with output_text

    Agent--)AppIns: Log trace:<br/>invoke_agent + chat metrics
    Note over AppIns: AppDependencies table<br/>invoke_agent: ~2-3s<br/>chat apim-gateway/gpt-4o-mini
```

## Flow 2: Cross-Region Agent (eastus2 → westus — gpt-4o)

```mermaid
sequenceDiagram
    autonumber
    participant User as 👤 User / Client
    participant Agent as 🤖 Agent Service<br/>(cross-region-westus-agent)
    participant ConnStore as 🔌 Connection Store<br/>(projectcdpy)
    participant PE_APIM as 🔗 APIM Private Endpoint<br/>(eastus2 pe-subnet)
    participant APIM as 🔀 APIM Gateway<br/>(aiservicescdpyapim, eastus2)
    participant VNetInt as 🔄 APIM VNet Integration<br/>(apim-subnet, eastus2)
    participant PE_WUS as 🔗 OpenAI Private Endpoint<br/>(eastus2 pe-subnet)
    participant LLM_WUS as 🧠 Azure OpenAI<br/>(cdpyopenai-westus, westus)
    participant AppIns as 📈 App Insights

    User->>+Agent: POST /responses<br/>agent: cross-region-westus-agent

    Agent->>+ConnStore: Resolve model<br/>"apim-gateway-westus/gpt-4o"
    ConnStore-->>-Agent: Connection: apim-gateway-westus<br/>Target: https://apim.azure-api.net/openai-westus<br/>Auth: ApiKey

    Agent->>+PE_APIM: POST /openai-westus/deployments/gpt-4o<br/>/chat/completions
    Note over PE_APIM: Private endpoint → APIM

    PE_APIM->>+APIM: Forward (private link)
    APIM->>APIM: Apply policy:<br/>managed-identity auth
    APIM->>APIM: Acquire Entra token (MI)

    Note over APIM,VNetInt: Outbound via apim-subnet<br/>(Microsoft.Web/serverFarms delegation)
    APIM->>+VNetInt: Route outbound through VNet

    VNetInt->>+PE_WUS: POST to cdpyopenai-westus<br/>/openai/deployments/gpt-4o/chat/completions<br/>Authorization: Bearer (MI token)
    Note over PE_WUS: Private endpoint in eastus2<br/>resolves westus OpenAI<br/>via privatelink.openai.azure.com<br/>192.168.1.14

    PE_WUS->>+LLM_WUS: Forward (private link,<br/>cross-region backbone)
    Note over LLM_WUS: gpt-4o inference<br/>in westus region
    LLM_WUS-->>-PE_WUS: Chat completion response

    PE_WUS-->>-VNetInt: Response
    VNetInt-->>-APIM: Response
    APIM-->>-PE_APIM: Response
    PE_APIM-->>-Agent: Model response

    Agent-->>-User: Response with output_text

    Agent--)AppIns: Log trace:<br/>invoke_agent + chat metrics
```

## Flow 3: Marketing Pipeline Workflow (Sequential)

```mermaid
sequenceDiagram
    autonumber
    participant User as 👤 User / Client
    participant App as 📦 marketing-pipeline-app
    participant WF as ⚡ Workflow Engine<br/>(marketing-pipeline)
    participant Analyst as 🤖 marketing-analyst
    participant Writer as 🤖 marketing-copywriter
    participant Editor as 🤖 marketing-editor
    participant APIM as 🔀 APIM Gateway
    participant LLM as 🧠 AI Services<br/>(gpt-4o-mini)
    participant AppIns as 📈 App Insights

    User->>+App: POST /applications/marketing-pipeline-app<br/>/protocols/openai/responses<br/>input: "Describe a smart water bottle..."

    App->>+WF: Route to workflow<br/>marketing-pipeline:v1

    Note over WF: Step 1: Analyst

    WF->>+Analyst: InvokeAzureAgent<br/>input: user message
    Analyst->>APIM: apim-gateway/gpt-4o-mini<br/>chat completion
    APIM->>LLM: managed identity auth
    LLM-->>APIM: Analysis (features, audience, USPs)
    APIM-->>Analyst: Response
    Analyst-->>-WF: Save to Local.LatestMessage

    Note over WF: Step 2: Copywriter

    WF->>+Writer: InvokeAzureAgent<br/>input: analyst output
    Writer->>APIM: apim-gateway/gpt-4o-mini<br/>chat completion
    APIM->>LLM: managed identity auth
    LLM-->>APIM: Marketing copy (~150 words)
    APIM-->>Writer: Response
    Writer-->>-WF: Save to Local.LatestMessage

    Note over WF: Step 3: Editor

    WF->>+Editor: InvokeAzureAgent<br/>input: copywriter output
    Editor->>APIM: apim-gateway/gpt-4o-mini<br/>chat completion
    APIM->>LLM: managed identity auth
    LLM-->>APIM: Polished final copy
    APIM-->>Editor: Response
    Editor-->>-WF: Save to Local.LatestMessage

    WF-->>-App: Workflow complete<br/>(3 message outputs)
    App-->>-User: Final polished copy + intermediate outputs

    WF--)AppIns: Log traces:<br/>3x invoke_agent + 3x chat
```

## Flow 4: Teams Integration (Private Agent via App Gateway + APIM)

```mermaid
sequenceDiagram
    autonumber
    participant Teams as 💬 Teams User
    participant Channel as 📡 Microsoft<br/>Channel Adapter
    participant AppGW as 🛡️ Application Gateway<br/>(WAF v2, TLS)
    participant APIM as 🔀 APIM<br/>(JWT validation)
    participant PE as 🔗 Private Endpoint<br/>(pe-subnet)
    participant Agent as 🤖 Foundry Agent<br/>(Activity Protocol)
    participant LLM as 🧠 AI Services
    participant AppIns as 📈 App Insights

    Teams->>+Channel: Send chat message
    Channel->>Channel: Acquire JWT token<br/>(iss: api.botframework.com<br/>aud: Bot Client ID)

    Channel->>+AppGW: POST https://agent.yourcompany.com/bot<br/>Authorization: Bearer {JWT}
    Note over AppGW: TLS termination<br/>with custom certificate<br/>WAF inspection

    AppGW->>+APIM: Forward to APIM backend
    APIM->>APIM: validate-jwt policy:<br/>✓ Signature (Microsoft keys)<br/>✓ Issuer = api.botframework.com<br/>✓ Audience = Bot Client ID<br/>✓ Token not expired

    APIM->>+PE: Forward to Activity Protocol URL<br/>(private endpoint)
    PE->>+Agent: Deliver message<br/>(private link)

    Agent->>LLM: Process with model<br/>(via APIM gateway)
    LLM-->>Agent: Model response

    Agent-->>-PE: Activity Protocol response
    PE-->>-APIM: Response
    APIM-->>-AppGW: Response
    AppGW-->>-Channel: Response

    Note over Agent,Channel: Reply path (separate connection)
    Agent->>Channel: POST https://smba.trafficmanager.net<br/>Reply message to Teams
    Channel-->>-Teams: Display agent response

    Agent--)AppIns: Log trace
```
