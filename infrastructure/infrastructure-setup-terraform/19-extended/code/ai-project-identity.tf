# -----------------------------------------------------------------------------
# AI Foundry project + connections (Storage, AI Search, Cosmos DB)
# Mirrors Bicep:
#   - ai-project-identity.bicep
#   - format-project-workspace-id.bicep (handled in locals.tf)
# -----------------------------------------------------------------------------

resource "azapi_resource" "ai_project" {
  type                      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  name                      = local.project_name
  parent_id                 = azapi_resource.ai_account.id
  location                  = var.location
  schema_validation_enabled = false

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      description = var.project_description
      displayName = var.display_name
    }
  }

  # internalId is used downstream to derive the workspace GUID.
  response_export_values = ["identity", "properties.internalId"]

  depends_on = [
    azurerm_private_endpoint.ai_account,
    azurerm_private_endpoint.search,
    azurerm_private_endpoint.storage,
    azurerm_private_endpoint.cosmos,
  ]
}

locals {
  ai_project_principal_id = azapi_resource.ai_project.output.identity.principalId
}

# ---- Cosmos DB connection ---------------------------------------------------
resource "azapi_resource" "project_connection_cosmosdb" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = local.cosmos_name
  parent_id                 = azapi_resource.ai_project.id
  schema_validation_enabled = false

  body = {
    properties = {
      category = "CosmosDB"
      target   = local.effective_cosmos_endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = local.effective_cosmos_id
        location   = var.location
      }
    }
  }
}

# ---- Storage (AzureStorageAccount) connection -------------------------------
resource "azapi_resource" "project_connection_storage" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = local.storage_name
  parent_id                 = azapi_resource.ai_project.id
  schema_validation_enabled = false

  body = {
    properties = {
      category = "AzureStorageAccount"
      target   = local.effective_storage_blob
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = local.effective_storage_id
        location   = var.location
      }
    }
  }
}

# ---- AI Search connection ---------------------------------------------------
resource "azapi_resource" "project_connection_search" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = local.search_name
  parent_id                 = azapi_resource.ai_project.id
  schema_validation_enabled = false

  body = {
    properties = {
      category = "CognitiveSearch"
      target   = "https://${local.search_name}.search.windows.net"
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = local.effective_search_id
        location   = var.location
      }
    }
  }
}
