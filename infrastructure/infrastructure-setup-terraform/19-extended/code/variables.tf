# ---------------------------------------------------------------------
# Core / location
# ---------------------------------------------------------------------
variable "subscription_id" {
  description = "Subscription ID to deploy into. If null, uses az login context."
  type        = string
  default     = null
}

variable "location" {
  description = "Location for all resources."
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Resource group name. If null, a new one named rg-<ai_services>-<suffix> is created."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------
# AI Foundry account / model
# ---------------------------------------------------------------------
variable "ai_services" {
  description = "Name prefix for your AI Services resource."
  type        = string
  default     = "aiservices"
}

variable "model_name" {
  description = "The name of the model to deploy."
  type        = string
  default     = "gpt-4o-mini"
}

variable "model_format" {
  description = "The provider of your model."
  type        = string
  default     = "OpenAI"
}

variable "model_version" {
  description = "The version of your model."
  type        = string
  default     = "2024-07-18"
}

variable "model_sku_name" {
  description = "The sku of your model deployment."
  type        = string
  default     = "GlobalStandard"
}

variable "model_capacity" {
  description = "The tokens per minute (TPM) of your model deployment."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------
# Project
# ---------------------------------------------------------------------
variable "first_project_name" {
  description = "Name prefix for your project resource."
  type        = string
  default     = "project"
}

variable "project_description" {
  description = "Project description."
  type        = string
  default     = "A project for the AI Foundry account with network secured deployed Agent"
}

variable "display_name" {
  description = "Display name of the project."
  type        = string
  default     = "network secured agent project"
}

variable "project_cap_host" {
  description = "Name of the project capability host to be created."
  type        = string
  default     = "caphostproj"
}

# ---------------------------------------------------------------------
# VNet / Subnets
# ---------------------------------------------------------------------
variable "vnet_name" {
  description = "Virtual Network name."
  type        = string
  default     = "agent-vnet-test"
}

variable "agent_subnet_name" {
  description = "Name of the agent subnet."
  type        = string
  default     = "agent-subnet"
}

variable "pe_subnet_name" {
  description = "Name of the private endpoint subnet."
  type        = string
  default     = "pe-subnet"
}

variable "mcp_subnet_name" {
  description = "Name of the MCP subnet for user-deployed Container Apps."
  type        = string
  default     = "mcp-subnet"
}

variable "existing_vnet_resource_id" {
  description = "Existing VNet full ARM Resource ID. Empty means create a new VNet."
  type        = string
  default     = ""
}

variable "vnet_address_prefix" {
  description = "Address space for the VNet (used only when creating a new VNet)."
  type        = string
  default     = ""
}

variable "agent_subnet_prefix" {
  description = "Address prefix for the agent subnet."
  type        = string
  default     = ""
}

variable "pe_subnet_prefix" {
  description = "Address prefix for the private endpoint subnet."
  type        = string
  default     = ""
}

variable "mcp_subnet_prefix" {
  description = "Address prefix for the MCP subnet."
  type        = string
  default     = ""
}

variable "apim_subnet_name" {
  description = "Name of the APIM subnet for outbound VNet integration."
  type        = string
  default     = "apim-subnet"
}

variable "apim_subnet_prefix" {
  description = "Address prefix for the APIM subnet."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------
# Existing dependent resources (optional)
# ---------------------------------------------------------------------
variable "ai_search_resource_id" {
  description = "Existing AI Search ARM Resource ID."
  type        = string
  default     = ""
}

variable "azure_storage_account_resource_id" {
  description = "Existing Storage Account ARM Resource ID."
  type        = string
  default     = ""
}

variable "azure_cosmosdb_account_resource_id" {
  description = "Existing Cosmos DB Account ARM Resource ID."
  type        = string
  default     = ""
}

variable "fabric_workspace_resource_id" {
  description = "Microsoft Fabric Workspace ARM Resource ID for Fabric private link connectivity."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------
# Existing DNS zones
# ---------------------------------------------------------------------
variable "existing_dns_zones" {
  description = "Map of private DNS zone FQDNs to resource group names. Empty value means the zone will be created."
  type        = map(string)
  default = {
    "privatelink.services.ai.azure.com"       = ""
    "privatelink.openai.azure.com"            = ""
    "privatelink.cognitiveservices.azure.com" = ""
    "privatelink.search.windows.net"          = ""
    "privatelink.blob.core.windows.net"       = ""
    "privatelink.documents.azure.com"         = ""
    "privatelink.fabric.microsoft.com"        = ""
    "privatelink.azure-api.net"               = ""
  }
}

# ---------------------------------------------------------------------
# API Management (optional)
# ---------------------------------------------------------------------
variable "deploy_api_management" {
  description = "Deploy an API Management service."
  type        = bool
  default     = false
}

variable "api_management_resource_id" {
  description = "Existing APIM ARM Resource ID. If set, the existing resource is used instead of creating one."
  type        = string
  default     = ""
}

variable "api_management_sku" {
  description = "APIM SKU (only StandardV2 and PremiumV2 support private endpoints)."
  type        = string
  default     = "StandardV2"
  validation {
    condition     = contains(["StandardV2", "PremiumV2"], var.api_management_sku)
    error_message = "api_management_sku must be StandardV2 or PremiumV2."
  }
}

variable "api_management_capacity" {
  description = "APIM capacity (scale units)."
  type        = number
  default     = 1
}

variable "publisher_email" {
  description = "Publisher email for APIM."
  type        = string
  default     = "apim-admin@contoso.com"
}

variable "publisher_name" {
  description = "Publisher name for APIM."
  type        = string
  default     = "AI Foundry"
}

variable "apim_connection_name" {
  description = "Name of the APIM gateway connection on the project."
  type        = string
  default     = "apim-gateway"
}

variable "apim_inference_api_version" {
  description = "API version used for inference calls through APIM."
  type        = string
  default     = "2024-10-21"
}

variable "apim_model_deployments" {
  description = "Static model deployments to expose through the APIM gateway."
  type        = list(any)
  default     = []
}

# ---------------------------------------------------------------------
# App Insights (optional)
# ---------------------------------------------------------------------
variable "deploy_application_insights" {
  description = "Deploy Application Insights for agent tracing and logging."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------
# Bastion / Jumpbox (optional)
# ---------------------------------------------------------------------
variable "deploy_bastion" {
  description = "Deploy Azure Bastion and a jump box VM."
  type        = bool
  default     = false
}

variable "bastion_subnet_prefix" {
  description = "Address prefix for AzureBastionSubnet (minimum /26)."
  type        = string
  default     = "192.168.4.0/26"
}

variable "jumpbox_subnet_prefix" {
  description = "Address prefix for the jump box subnet."
  type        = string
  default     = "192.168.6.0/24"
}

variable "jumpbox_admin_password" {
  description = "Admin password for the jump box VM."
  type        = string
  default     = ""
  sensitive   = true
}

variable "jumpbox_admin_username" {
  description = "Admin username for the jump box VM."
  type        = string
  default     = "azureuser"
}

# ---------------------------------------------------------------------
# VPN Gateway (optional)
# ---------------------------------------------------------------------
variable "deploy_vpn_gateway" {
  description = "Deploy a VPN Gateway."
  type        = bool
  default     = false
}

variable "gateway_subnet_prefix" {
  description = "Address prefix for GatewaySubnet (minimum /27)."
  type        = string
  default     = "192.168.255.0/27"
}

variable "vpn_gateway_sku" {
  description = "VPN Gateway SKU."
  type        = string
  default     = "VpnGw1"
  validation {
    condition     = contains(["VpnGw1", "VpnGw2", "VpnGw3", "VpnGw1AZ", "VpnGw2AZ", "VpnGw3AZ"], var.vpn_gateway_sku)
    error_message = "vpn_gateway_sku must be a valid VpnGw SKU."
  }
}

# ---------------------------------------------------------------------
# Cross-region OpenAI (optional)
# ---------------------------------------------------------------------
variable "deploy_cross_region_openai" {
  description = "Deploy an Azure OpenAI resource in a different region and connect it to the Foundry account."
  type        = bool
  default     = false
}

variable "cross_region_location" {
  description = "Azure region for the cross-region Azure OpenAI resource."
  type        = string
  default     = ""
}

variable "cross_region_model_name" {
  description = "Model name to deploy in the cross-region OpenAI resource."
  type        = string
  default     = "gpt-4o"
}

variable "cross_region_model_version" {
  description = "Model version for the cross-region deployment."
  type        = string
  default     = "2024-11-20"
}

# ---------------------------------------------------------------------
# Workflow (optional)
# ---------------------------------------------------------------------
variable "deploy_workflow" {
  description = "Deploy the marketing pipeline workflow with published application."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------
# Teams publishing (optional)
# ---------------------------------------------------------------------
variable "deploy_teams_publishing" {
  description = "Deploy Teams publishing infrastructure (App Gateway + Bot Service + Teams Channel)."
  type        = bool
  default     = false
}

variable "teams_custom_domain" {
  description = "Custom domain for the Bot messaging endpoint (e.g., agent.yourcompany.com)."
  type        = string
  default     = ""
}

variable "teams_agent_name" {
  description = "Name of the agent to publish to Teams."
  type        = string
  default     = "marketing-pipeline"
}

variable "teams_application_name" {
  description = "Name for the Teams Agent Application."
  type        = string
  default     = "marketing-pipeline-teams"
}

variable "app_gw_subnet_prefix" {
  description = "Address prefix for the Application Gateway subnet."
  type        = string
  default     = "192.168.5.0/24"
}

variable "bastion_name" {
  description = "Name for the Bastion host."
  type        = string
  default     = "bastion"
}

variable "vm_name" {
  description = "Name for the jump box VM."
  type        = string
  default     = "jumpbox"
}

variable "vm_size" {
  description = "VM size for the jump box."
  type        = string
  default     = "Standard_B2s_v2"
}

variable "vm_admin_username" {
  description = "Admin username for the jump box VM (alias of jumpbox_admin_username)."
  type        = string
  default     = "azureuser"
}

variable "vm_admin_password" {
  description = "Admin password for the jump box VM."
  type        = string
  default     = ""
  sensitive   = true
}

variable "jumpbox_subnet_name" {
  description = "Name for the jump box subnet."
  type        = string
  default     = "jumpbox-subnet"
}

variable "vpn_gateway_name" {
  description = "Name for the VPN Gateway."
  type        = string
  default     = "vpn-gateway"
}

variable "vpn_gateway_subnet_prefix" {
  description = "Address prefix for GatewaySubnet."
  type        = string
  default     = "192.168.255.0/27"
}

variable "vpn_type" {
  description = "VPN gateway type."
  type        = string
  default     = "RouteBased"
  validation {
    condition     = contains(["RouteBased", "PolicyBased"], var.vpn_type)
    error_message = "vpn_type must be RouteBased or PolicyBased."
  }
}

variable "cross_region_model_sku" {
  description = "Model SKU for the cross-region OpenAI deployment."
  type        = string
  default     = "GlobalStandard"
}

variable "cross_region_model_capacity" {
  description = "Model capacity (TPM) for the cross-region OpenAI deployment."
  type        = number
  default     = 30
}

variable "workflow_agent_model" {
  description = "Model reference used by the workflow agents (e.g., 'apim-gateway/gpt-4o-mini' or 'gpt-4o-mini')."
  type        = string
  default     = "gpt-4o-mini"
}

variable "workflow_name" {
  description = "Name of the workflow agent."
  type        = string
  default     = "marketing-pipeline"
}

variable "workflow_application_name" {
  description = "Name of the published Agent Application for the workflow."
  type        = string
  default     = "marketing-pipeline-app"
}

variable "workflow_deployment_name" {
  description = "Name of the workflow deployment."
  type        = string
  default     = "marketing-pipeline-deployment"
}

variable "teams_agent_version" {
  description = "Version of the agent to publish to Teams (empty = latest)."
  type        = string
  default     = ""
}

variable "teams_deployment_name" {
  description = "Name for the Teams Agent Deployment."
  type        = string
  default     = "teams-deployment"
}

variable "teams_bot_tenant_id" {
  description = "Azure AD tenant id for the Bot Service. Empty = current tenant."
  type        = string
  default     = ""
}

variable "teams_bot_client_id" {
  description = "Bot msaAppId (Agent Application default instance identity client id). Provide after running the teams publish script — required for a fully automated re-apply."
  type        = string
  default     = ""
}

variable "teams_key_vault_name" {
  description = "Key Vault name for the Teams TLS certificate. Empty = derived from account name."
  type        = string
  default     = ""
}

variable "teams_tls_cert_name" {
  description = "Name of the TLS certificate in Key Vault."
  type        = string
  default     = "teams-bot-tls"
}

variable "teams_apim_private_ip" {
  description = "APIM private IP (used in App Gateway backend pool when APIM is private). Empty = use FQDN."
  type        = string
  default     = ""
}

variable "teams_activity_protocol_url" {
  description = "Activity Protocol URL for the published application. Populated by the teams publish script; set manually if running App Gateway separately."
  type        = string
  default     = ""
}
