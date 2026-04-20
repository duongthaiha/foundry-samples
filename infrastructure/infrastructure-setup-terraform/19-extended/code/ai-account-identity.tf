# -----------------------------------------------------------------------------
# AI Foundry (Cognitive Services) account + model deployment
# Mirrors Bicep: modules-network-secured/ai-account-identity.bicep
# -----------------------------------------------------------------------------

resource "azapi_resource" "ai_account" {
  type                      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name                      = local.account_name
  parent_id                 = azurerm_resource_group.rg.id
  location                  = var.location
  schema_validation_enabled = false

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    properties = {
      allowProjectManagement = true
      customSubDomainName    = local.account_name
      # Public access must be Enabled (not Disabled) for the `bypass: AzureServices`
      # network ACL to take effect. With defaultAction=Deny, no public traffic is
      # allowed except trusted Microsoft services (e.g. Azure AI Search indexer
      # skills like ChatCompletionSkill that call OpenAI chat completions).
      # All non-trusted traffic still flows via the private endpoints in
      # private-endpoint-and-dns.tf.
      publicNetworkAccess = "Enabled"
      disableLocalAuth    = false
      networkAcls = {
        defaultAction       = "Deny"
        virtualNetworkRules = []
        ipRules             = []
        bypass              = "AzureServices"
      }
      networkInjections = [
        {
          scenario                   = "agent"
          subnetArmId                = local.agent_subnet_id
          useMicrosoftManagedNetwork = false
        }
      ]
    }
  }

  response_export_values = ["identity", "properties.endpoint"]
}

locals {
  ai_account_principal_id = azapi_resource.ai_account.output.identity.principalId
}

# ---- Model deployment -------------------------------------------------------
resource "azapi_resource" "model_deployment" {
  type                      = "Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview"
  name                      = var.model_name
  parent_id                 = azapi_resource.ai_account.id
  schema_validation_enabled = false

  body = {
    sku = {
      name     = var.model_sku_name
      capacity = var.model_capacity
    }
    properties = {
      model = {
        name    = var.model_name
        format  = var.model_format
        version = var.model_version
      }
    }
  }
}
