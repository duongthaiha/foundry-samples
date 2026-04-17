output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "account_name" {
  value = azapi_resource.ai_account.name
}

output "account_id" {
  value = azapi_resource.ai_account.id
}

output "account_endpoint" {
  value = try(azapi_resource.ai_account.output.properties.endpoint, null)
}

output "project_name" {
  value = azapi_resource.ai_project.name
}

output "project_id" {
  value = azapi_resource.ai_project.id
}

output "project_workspace_id" {
  value = local.project_workspace_id
}

output "virtual_network_id" {
  value = local.virtual_network_id
}

output "agent_subnet_id" { value = local.agent_subnet_id }
output "pe_subnet_id" { value = local.pe_subnet_id }
output "mcp_subnet_id" { value = local.mcp_subnet_id }

output "ai_search_id" {
  value = local.search_passed_in ? data.azurerm_search_service.existing[0].id : azurerm_search_service.search[0].id
}

output "storage_account_id" {
  value = local.storage_passed_in ? data.azurerm_storage_account.existing[0].id : azurerm_storage_account.storage[0].id
}

output "cosmos_db_id" {
  value = local.cosmos_passed_in ? data.azurerm_cosmosdb_account.existing[0].id : azurerm_cosmosdb_account.cosmos[0].id
}

output "api_management_name" {
  value = local.apim_configured ? local.apim_name : null
}

output "application_insights_connection_string" {
  value     = var.deploy_application_insights ? azurerm_application_insights.app[0].connection_string : null
  sensitive = true
}

output "bastion_name" {
  value = var.deploy_bastion ? azurerm_bastion_host.bastion[0].name : null
}

output "vpn_gateway_public_ip" {
  value = var.deploy_vpn_gateway ? azurerm_public_ip.vpn[0].ip_address : null
}

output "cross_region_openai_endpoint" {
  value = var.deploy_cross_region_openai ? try(azapi_resource.cross_region_openai[0].output.properties.endpoint, null) : null
}

output "teams_app_gateway_public_ip" {
  value = var.deploy_teams_publishing ? azurerm_public_ip.app_gw[0].ip_address : null
}
