# Minimal deployment — creates AI Foundry account (private), VNet, Search,
# Storage, Cosmos, private endpoints, capability host, Application Insights.
location    = "eastus2"
ai_services = "aiservices"

# Optional features — turn on as needed.
deploy_application_insights = true
deploy_api_management       = false
deploy_bastion              = false
deploy_vpn_gateway          = false
deploy_cross_region_openai  = false
deploy_workflow             = false
deploy_teams_publishing     = false

# Example: use your own VNet / dependent resources
# existing_vnet_resource_id            = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>"
# ai_search_resource_id                = "/subscriptions/..."
# azure_storage_account_resource_id    = "/subscriptions/..."
# azure_cosmosdb_account_resource_id   = "/subscriptions/..."
