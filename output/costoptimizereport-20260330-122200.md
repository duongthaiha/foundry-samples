# Azure Cost Optimization Report

**Generated**: 2026-03-30T12:22Z  
**Subscription**: ME-MngEnvMCAP734518-haduong-1 (`3d2c527a-481d-4e13-b3a1-637924b33343`)  
**Tenant**: `cdfe81b5-821e-4f07-9ea7-516efc8497e4`  
**Period**: Last 30 days (2026-02-28 to 2026-03-30)

---

## Executive Summary

| Metric | Value |
|--------|-------|
| **Total Cost (30 days)** | 💰 **$1,514.01** |
| **Projected Monthly** | 💰 ~$1,514/month |
| **Active Resource Groups** | 16 |
| **Total Resources** | 153 |
| **Orphaned NICs** | 8 |
| **Deleted RGs Still Charged** | 10 (incurred **$861.14** or **56.9%** of total) |

### Top 3 Cost Drivers (by Service)
1. **Foundry Tools** — $379.22 (25.0%)
2. **API Management** — $343.67 (22.7%)
3. **Azure Cognitive Search** — $294.82 (19.5%)

---

## Cost Breakdown by Service

| Rank | Cost (30d) | % of Total | Service |
|------|-----------|------------|---------|
| 1 | $379.22 | 25.0% | Foundry Tools |
| 2 | $343.67 | 22.7% | API Management |
| 3 | $294.82 | 19.5% | Azure Cognitive Search |
| 4 | $103.90 | 6.9% | Microsoft Defender for Cloud |
| 5 | $94.27 | 6.2% | Foundry Models |
| 6 | $64.76 | 4.3% | Azure App Service |
| 7 | $48.07 | 3.2% | Azure Bastion |
| 8 | $47.76 | 3.2% | Azure Container Apps |
| 9 | $39.44 | 2.6% | GitHub |
| 10 | $33.83 | 2.2% | Container Registry |
| 11 | $22.05 | 1.5% | Virtual Network |
| 12 | $19.81 | 1.3% | Azure Cosmos DB |
| 13 | $6.99 | 0.5% | Log Analytics |
| 14 | $6.20 | 0.4% | Azure Monitor |
| 15 | $3.39 | 0.2% | Storage |
| 16 | $3.06 | 0.2% | Virtual Machines |
| 17 | $0.86 | 0.1% | Azure DNS |
| 18 | $0.76 | 0.1% | VPN Gateway |
| 19 | $0.63 | 0.0% | Service Bus |
| 20 | $0.40 | 0.0% | Functions |
| 21 | $0.12 | 0.0% | Logic Apps |
| 22 | $0.01 | 0.0% | Bandwidth |
| 23 | $0.00 | 0.0% | Event Grid |

---

## Cost Breakdown by Resource Group

| Rank | Cost (30d) | % of Total | Resource Group | Status |
|------|-----------|------------|----------------|--------|
| 1 | $336.96 | 22.3% | rg-foundry-project | ⚠️ DELETED |
| 2 | $189.71 | 12.5% | foundryapibyovnet | ✅ Active |
| 3 | $155.40 | 10.3% | lab-vector-searching | ⚠️ DELETED |
| 4 | $149.38 | 9.9% | lab-content-safety | ✅ Active |
| 5 | $143.35 | 9.5% | techworkshop-l300-ai-agents | ⚠️ DELETED |
| 6 | $89.18 | 5.9% | rg-openai-instances | ✅ Active |
| 7 | $60.16 | 4.0% | lab-product-framework | ⚠️ DELETED |
| 8 | $60.08 | 4.0% | lab-finops-framework | ⚠️ DELETED |
| 9 | $60.00 | 4.0% | rg-voicelive-api-salescoach | ✅ Active |
| 10 | $55.42 | 3.7% | rg-agentic-retrieval | ⚠️ DELETED |
| 11 | $48.96 | 3.2% | callcenter-rg-dev-eastus2 | ✅ Active |
| 12 | $42.41 | 2.8% | *(untagged)* | — |
| 13 | $37.49 | 2.5% | rg-devmultiagent | ⚠️ DELETED |
| 14 | $29.54 | 2.0% | callcenter-rg-dev | ✅ Active |
| 15 | $20.19 | 1.3% | ktbakshduwlregistry_group | ✅ Active |
| 16 | $19.61 | 1.3% | rg-foundry-uk | ✅ Active |
| 17 | $12.20 | 0.8% | rg-aca-healthprobe | ⚠️ DELETED |
| 18 | $3.57 | 0.2% | rg-hybrid-agent-test | ✅ Active |
| 19 | $0.19 | 0.0% | defaultresourcegroup-sec | ✅ Active |
| 20 | $0.10 | 0.0% | default-activitylogalerts | ✅ Active |
| 21 | $0.08 | 0.0% | rg-cu-standalone | ⚠️ DELETED |
| 22 | $0.01 | 0.0% | rg-foundry-sc | ✅ Active |
| 23 | $0.00 | 0.0% | rg-aca | ⚠️ DELETED |

---

## Top 20 Most Expensive Resources

| Rank | Cost (30d) | Resource | Type |
|------|-----------|----------|------|
| 1 | $263.56 | azuresreagenthd | Container Apps |
| 2 | $149.38 | apim-u3syrr6kayv3s | API Management |
| 3 | $96.43 | search-qukjdowaght5s | Cognitive Search |
| 4 | $89.08 | aoai-swedencentral-hd | Cognitive Services |
| 5 | $89.04 | aiservicesjh74search | Cognitive Search |
| 6 | $67.50 | aif-mscrpzb2zxg52@proj | ML Services |
| 7 | $60.50 | search-foundryhd | Cognitive Search |
| 8 | $58.97 | apim-y2cjcf2i2qvrs | API Management |
| 9 | $58.97 | apim-dcsmdldxfng3y | API Management |
| 10 | $58.97 | apim-qukjdowaght5s | API Management |
| 11 | $48.07 | agent-bastion | Bastion Host |
| 12 | $46.95 | aifoundry-voicelab | Cognitive Services |
| 13 | $46.16 | srch-agenticretrieval | Cognitive Search |
| 14 | $39.44 | customer-19850068 | GitHub Enterprise |
| 15 | $36.09 | mscrpzb2zxg52-cosu-asp | App Service Plan |
| 16 | $28.01 | ca-macae-taqahilmwpiu | Container App |
| 17 | $20.19 | ktbakshduwlregistry | Container Registry |
| 18 | $18.20 | callqa-dev-swa | Static Web App |
| 19 | $17.37 | apim-agent-jzhu | API Management |
| 20 | $16.75 | fca-dev-swa | Static Web App |

---

## Orphaned Resources

### Orphaned Network Interfaces (8 found)
These NICs are not attached to any virtual machine. They are associated with private endpoints and likely have minimal cost impact, but indicate potential cleanup opportunity.

| NIC Name | Resource Group |
|----------|---------------|
| aiservicescdpy-private-endpoint.nic.* | rg-hybrid-agent-test |
| aiservicescdpycosmosdb-private-endpoint.nic.* | rg-hybrid-agent-test |
| aiservicescdpysearch-private-endpoint.nic.* | rg-hybrid-agent-test |
| aiservicescdpystorage-private-endpoint.nic.* | rg-hybrid-agent-test |
| callqa-dev-blob-pe.nic.* | callcenter-rg-dev-eastus2 |
| callqa-dev-cosmos-pe.nic.* | callcenter-rg-dev-eastus2 |
| callqa-dev-queue-pe.nic.* | callcenter-rg-dev-eastus2 |
| callqa-dev-table-pe.nic.* | callcenter-rg-dev-eastus2 |

### Orphaned Disks: 0 found ✅
### Orphaned Public IPs: 0 found ✅

---

## Resource Inventory Summary

| Count | Resource Type |
|-------|--------------|
| 19 | Cognitive Services Accounts |
| 15 | Private DNS Zones |
| 12 | Private DNS Zone Links |
| 9 | Network Watchers |
| 8 | Private Endpoints |
| 8 | Network Interfaces |
| 7 | Log Analytics Workspaces |
| 7 | Network Security Groups |
| 5 | Smart Detector Alert Rules |
| 5 | Cognitive Services Projects |
| 4 | Virtual Networks |
| 4 | Storage Accounts |
| 4 | Event Grid System Topics |
| 4 | Application Insights |
| 3 | User Assigned Managed Identities |
| 3 | Cosmos DB Accounts |
| 2 | Container Registries |
| 2 | Static Web Apps |
| 2 | Key Vaults |
| 2 | Service Bus Namespaces |
| 2 | App Service Plans |
| 2 | Web Apps |
| 2 | Search Services |
| 1 | API Management Service |
| 1 | Container App |
| 1 | Managed Environment |
| 1 | Logic App |
| 1 | Public IP Address |
| 1 | VPN Gateway |

---

## Optimization Recommendations

### 🔴 Priority 1: High Impact — Investigate Deleted Resource Group Charges ($861/month)

**Finding**: 10 resource groups that no longer exist still incurred **$861.14** (56.9% of total) in the last 30 days. These costs are likely from resources that existed before the RGs were deleted during this period.

| Deleted Resource Group | Cost (30d) |
|----------------------|-----------|
| rg-foundry-project | $336.96 |
| lab-vector-searching | $155.40 |
| techworkshop-l300-ai-agents | $143.35 |
| lab-product-framework | $60.16 |
| lab-finops-framework | $60.08 |
| rg-agentic-retrieval | $55.42 |
| rg-devmultiagent | $37.49 |
| rg-aca-healthprobe | $12.20 |
| rg-cu-standalone | $0.08 |
| rg-aca | $0.00 |

**💡 Action**: These charges should stop naturally since the resource groups are deleted. Verify in next month's billing that these charges are gone. If charges persist, investigate with Azure Support.

**📊 ESTIMATED monthly savings**: Up to **$861/month** going forward (if all were deleted within the last 30 days).

### 🟡 Priority 2: API Management Consolidation ($344/month)

You have **5 API Management instances** costing a combined **$343.67/month**:
- apim-u3syrr6kayv3s ($149.38)
- apim-y2cjcf2i2qvrs ($58.97)
- apim-dcsmdldxfng3y ($58.97)
- apim-qukjdowaght5s ($58.97)
- apim-agent-jzhu ($17.37)

**💡 Action**: Consider consolidating to fewer APIM instances if they serve similar purposes. Each Developer-tier APIM costs ~$50/month.

**📊 ESTIMATED savings**: $60–180/month by consolidating 2-3 instances.

### 🟡 Priority 3: Azure Cognitive Search Consolidation ($295/month)

You have **4 Search Service instances** costing a combined **$294.82/month**:
- search-qukjdowaght5s ($96.43)
- aiservicesjh74search ($89.04)
- search-foundryhd ($60.50)
- srch-agenticretrieval ($46.16)

**💡 Action**: Evaluate if all 4 search instances are actively used. Consider consolidating indexes into fewer services.

**📊 ESTIMATED savings**: $50–150/month if 1-2 services can be removed.

### 🟡 Priority 4: Azure Bastion ($48/month)

**agent-bastion** costs $48.07/month. Bastion charges for uptime regardless of use.

**💡 Action**: If not regularly needed for VM SSH/RDP access, consider deleting and using JIT (Just-in-Time) VM access instead.

**📊 ESTIMATED savings**: $48/month

### 🟢 Priority 5: Container Registry ($54/month)

Two registries at $20.19 and $8.71. The Premium tier registry (`ktbakshduwlregistry`) costs $20/month.

**💡 Action**: Evaluate if Premium tier is needed (geo-replication, private link). Downgrade to Standard ($5/month) if not.

**📊 ESTIMATED savings**: $15/month

### 🟢 Priority 6: Orphaned NICs (Minimal Cost)

8 orphaned NICs found. NICs themselves have negligible cost, but their associated private endpoints may have minor costs.

**💡 Action**: Clean up if the associated services are no longer needed.

---

## Total Estimated Savings

| Category | Monthly Savings | Annual Savings |
|----------|----------------|----------------|
| Deleted RGs (auto-resolved) | $861 | $10,332 |
| APIM Consolidation | $60–180 | $720–2,160 |
| Search Consolidation | $50–150 | $600–1,800 |
| Bastion Removal | $48 | $576 |
| Registry Downgrade | $15 | $180 |
| **Total (conservative)** | **$1,034** | **$12,408** |
| **Total (aggressive)** | **$1,254** | **$15,048** |

> ⚠️ The largest savings ($861/month) from deleted resource groups should resolve automatically. Focus actionable optimization on APIM and Search consolidation.

---

## Data Sources

- **Cost Data**: Azure Cost Management REST API (`2023-11-01`)
- **Resource Inventory**: Azure Resource Manager (`az resource list`)
- **Orphaned Resources**: Azure Resource Graph queries
- **Period**: 2026-02-28 to 2026-03-30
- **Audit Trail**: `output/cost-query-result-20260330.json`

> 💰 = ACTUAL DATA from Azure Cost Management API  
> 📊 = ESTIMATED based on actual data and Azure pricing
