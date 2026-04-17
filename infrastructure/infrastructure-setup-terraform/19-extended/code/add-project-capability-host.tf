# -----------------------------------------------------------------------------
# Capability host (project-level)
#
# Mirrors Bicep: modules-network-secured/add-project-capability-host.bicep
#
# The account-level capability host ("default") is auto-created by the backend
# when networkInjections are configured on the AI account, so we reference it
# as an existing resource rather than creating it (per repo convention).
# -----------------------------------------------------------------------------

resource "azapi_resource" "project_capability_host" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name                      = var.project_cap_host
  parent_id                 = azapi_resource.ai_project.id
  schema_validation_enabled = false

  body = {
    properties = {
      capabilityHostKind       = "Agents"
      vectorStoreConnections   = [azapi_resource.project_connection_search.name]
      storageConnections       = [azapi_resource.project_connection_storage.name]
      threadStorageConnections = [azapi_resource.project_connection_cosmosdb.name]
    }
  }

  depends_on = [
    # Pre-caphost role assignments
    azurerm_role_assignment.project_cosmos_operator,
    azurerm_role_assignment.project_storage_blob_contributor,
    azurerm_role_assignment.project_search_index_data_contributor,
    azurerm_role_assignment.project_search_service_contributor,
    azurerm_role_assignment.account_storage_blob_contributor,
    azurerm_role_assignment.account_search_index_data_contributor,
    azurerm_role_assignment.account_search_service_contributor,
    azurerm_role_assignment.search_mi_storage_blob_reader,
    azurerm_role_assignment.search_mi_cognitive_services_openai_user,
    azurerm_private_endpoint.ai_account,
    azurerm_private_endpoint.search,
    azurerm_private_endpoint.storage,
    azurerm_private_endpoint.cosmos,
  ]
}
