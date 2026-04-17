# -----------------------------------------------------------------------------
# Role assignments — consolidated from 12 small Bicep modules:
#   - azure-storage-account-role-assignment.bicep         (project -> SBDC)
#   - cosmosdb-account-role-assignment.bicep              (project -> Cosmos Operator)
#   - ai-search-role-assignments.bicep                    (project -> Search IDC + SSC)
#   - ai-account-to-search-role-assignment.bicep          (account -> Search IDC + SSC)
#   - ai-account-to-storage-role-assignment.bicep         (account -> SBDC)
#   - search-mi-to-storage-role-assignment.bicep          (search MI -> SBDR)
#   - search-mi-to-openai-role-assignment.bicep           (search MI -> Cog Svcs OpenAI User)
#   - blob-storage-container-role-assignments.bicep       (project -> SBDO w/ condition)
#   - cosmos-container-role-assignments.bicep             (project -> Cosmos Built-In DC)
#
# Built-in role definition GUIDs:
#   Storage Blob Data Contributor      ba92f5b4-2d11-453d-a403-e96b0029c9fe
#   Storage Blob Data Reader           acdd72a7-3385-48ef-bd42-f606fba81ae7
#   Storage Blob Data Owner            b7e6dc6d-f1e8-4753-8033-0f276bb0955b
#   Search Index Data Contributor      8ebe5a00-799e-43f5-93ac-243d3dce84a7
#   Search Service Contributor         7ca78c08-252a-4471-8644-bb5ff32d4ba0
#   Cosmos DB Operator                 230815da-be43-4aae-9cb4-875f7bd000aa
#   Cognitive Services OpenAI User     5e0bd9bd-7b93-4f28-af87-19fc36ad61bd
# -----------------------------------------------------------------------------

locals {
  role_ids = {
    storage_blob_data_contributor  = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
    storage_blob_data_reader       = "acdd72a7-3385-48ef-bd42-f606fba81ae7"
    storage_blob_data_owner        = "b7e6dc6d-f1e8-4753-8033-0f276bb0955b"
    search_index_data_contributor  = "8ebe5a00-799e-43f5-93ac-243d3dce84a7"
    search_service_contributor     = "7ca78c08-252a-4471-8644-bb5ff32d4ba0"
    cosmos_db_operator             = "230815da-be43-4aae-9cb4-875f7bd000aa"
    cognitive_services_openai_user = "5e0bd9bd-7b93-4f28-af87-19fc36ad61bd"
  }
}

# =============================================================================
# PRE-CAPHOST assignments
# =============================================================================

# ---- Project → Storage (Storage Blob Data Contributor) ----------------------
resource "azurerm_role_assignment" "project_storage_blob_contributor" {
  scope              = local.effective_storage_id
  role_definition_id = "/subscriptions/${local.storage_sub_id}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids.storage_blob_data_contributor}"
  principal_id       = local.ai_project_principal_id
  principal_type     = "ServicePrincipal"
}

# ---- Project → Cosmos (Cosmos DB Operator) ----------------------------------
resource "azurerm_role_assignment" "project_cosmos_operator" {
  scope              = local.effective_cosmos_id
  role_definition_id = "/subscriptions/${local.cosmos_sub_id}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids.cosmos_db_operator}"
  principal_id       = local.ai_project_principal_id
  principal_type     = "ServicePrincipal"
}

# ---- Project → Search (Search Index Data Contributor + Search Service Contributor) ----
resource "azurerm_role_assignment" "project_search_index_data_contributor" {
  scope              = local.effective_search_id
  role_definition_id = "/subscriptions/${local.search_sub_id}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids.search_index_data_contributor}"
  principal_id       = local.ai_project_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "project_search_service_contributor" {
  scope              = local.effective_search_id
  role_definition_id = "/subscriptions/${local.search_sub_id}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids.search_service_contributor}"
  principal_id       = local.ai_project_principal_id
  principal_type     = "ServicePrincipal"
}

# ---- Account → Storage (Storage Blob Data Contributor) ----------------------
resource "azurerm_role_assignment" "account_storage_blob_contributor" {
  scope              = local.effective_storage_id
  role_definition_id = "/subscriptions/${local.storage_sub_id}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids.storage_blob_data_contributor}"
  principal_id       = local.ai_account_principal_id
  principal_type     = "ServicePrincipal"
}

# ---- Account → Search (Search Index DC + Search Service Contributor) --------
resource "azurerm_role_assignment" "account_search_index_data_contributor" {
  scope              = local.effective_search_id
  role_definition_id = "/subscriptions/${local.search_sub_id}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids.search_index_data_contributor}"
  principal_id       = local.ai_account_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "account_search_service_contributor" {
  scope              = local.effective_search_id
  role_definition_id = "/subscriptions/${local.search_sub_id}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids.search_service_contributor}"
  principal_id       = local.ai_account_principal_id
  principal_type     = "ServicePrincipal"
}

# ---- Search MI → Storage (Storage Blob Data Reader) -------------------------
# Only assign when Search has a system-assigned identity principal we can read.
resource "azurerm_role_assignment" "search_mi_storage_blob_reader" {
  count              = local.effective_search_principal_id != null ? 1 : 0
  scope              = local.effective_storage_id
  role_definition_id = "/subscriptions/${local.storage_sub_id}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids.storage_blob_data_reader}"
  principal_id       = local.effective_search_principal_id
  principal_type     = "ServicePrincipal"
}

# ---- Search MI → Account (Cognitive Services OpenAI User) -------------------
resource "azurerm_role_assignment" "search_mi_cognitive_services_openai_user" {
  count              = local.effective_search_principal_id != null ? 1 : 0
  scope              = azapi_resource.ai_account.id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids.cognitive_services_openai_user}"
  principal_id       = local.effective_search_principal_id
  principal_type     = "ServicePrincipal"
}

# =============================================================================
# POST-CAPHOST assignments
# =============================================================================

# ---- Project → Storage Blob containers (Storage Blob Data Owner w/ condition) ----
# Matches Bicep conditionStr in blob-storage-container-role-assignments.bicep.
resource "azurerm_role_assignment" "project_storage_blob_data_owner" {
  scope              = local.effective_storage_id
  role_definition_id = "/subscriptions/${local.storage_sub_id}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids.storage_blob_data_owner}"
  principal_id       = local.ai_project_principal_id
  principal_type     = "ServicePrincipal"

  condition         = "((!(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read'})  AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/filter/action'}) AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write'}) ) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase '${local.project_workspace_guid}' AND @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringLikeIgnoreCase '*-azureml-agent'))"
  condition_version = "2.0"

  depends_on = [azapi_resource.project_capability_host]
}

# ---- Project → Cosmos containers (Cosmos Built-In Data Contributor) ---------
# Role def 00000000-0000-0000-0000-000000000002 is a data-plane role in Cosmos;
# we use azurerm_cosmosdb_sql_role_assignment to assign it.
resource "azurerm_cosmosdb_sql_role_assignment" "project_cosmos_data_contributor" {
  resource_group_name = local.cosmos_rg
  account_name        = local.cosmos_name
  role_definition_id  = "${local.effective_cosmos_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = local.ai_project_principal_id
  scope               = local.effective_cosmos_id

  depends_on = [azapi_resource.project_capability_host]
}
