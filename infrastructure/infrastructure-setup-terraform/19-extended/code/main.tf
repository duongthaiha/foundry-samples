# Hybrid Private Resources Setup for Azure AI Foundry Agents (19-extended)
# ------------------------------------------------------------------------
# Terraform conversion of:
#   infrastructure-setup-bicep/19-hybrid-private-resources-agent-setup
#
# This template creates an Azure AI Foundry account with public network
# access DISABLED, while keeping backend resources (AI Search, Cosmos DB,
# Storage) on private endpoints.
#
# Optional features are gated by `deploy_*` variables:
#   - deploy_api_management        → api-management.tf, apim-gateway-connection.tf
#   - deploy_application_insights  → application-insights.tf
#   - deploy_bastion               → bastion-jumpbox.tf
#   - deploy_vpn_gateway           → vpn-gateway.tf
#   - deploy_cross_region_openai   → cross-region-openai-connection.tf
#   - deploy_workflow              → workflow-deployment.tf
#   - deploy_teams_publishing      → teams-agent-publish-script.tf + teams-publishing-infra.tf
#
# See README.md for deployment guidance.

resource "azurerm_resource_group" "rg" {
  name     = coalesce(var.resource_group_name, "rg-${var.ai_services}-${local.unique_suffix}")
  location = var.location
}
