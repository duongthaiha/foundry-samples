# -----------------------------------------------------------------------------
# Shared Private Link: Search service -> AI Services account (openai_account)
# Mirrors Bicep: modules-network-secured/search-shared-private-link-to-aiservices.bicep
#
# Provides a private route that built-in indexer skills (e.g.
# AzureOpenAIEmbeddingSkill) automatically use when the resourceUri matches.
# Custom Web API skills like ChatCompletionSkill don't auto-route through SPL —
# those are covered by `publicNetworkAccess: Enabled` + `bypass: AzureServices`
# on the AI Services account (see ai-account-identity.tf).
#
# After the SPL is created, a local-exec (az CLI) approves the resulting
# Pending private endpoint connection on the AI Services account side.
# Idempotent: the script no-ops if the connection is already Approved.
# -----------------------------------------------------------------------------

locals {
  search_spl_name = "search-to-aiservices-openai"
}

resource "azapi_resource" "search_to_aiservices_spl" {
  type                      = "Microsoft.Search/searchServices/sharedPrivateLinkResources@2025-05-01"
  name                      = local.search_spl_name
  parent_id                 = local.effective_search_id
  schema_validation_enabled = false

  body = {
    properties = {
      privateLinkResourceId = azapi_resource.ai_account.id
      groupId               = "openai_account"
      requestMessage        = "Azure AI Search indexer skill access to AI Services (auto-approved by Terraform)"
    }
  }

  response_export_values = ["properties.status"]

  depends_on = [
    azapi_resource.ai_account,
    azurerm_search_service.search,
  ]
}

# Auto-approve the pending PE connection on the AI Services account.
# Uses the caller's az CLI (already authenticated for `terraform apply`).
resource "null_resource" "approve_search_aiservices_spl" {
  triggers = {
    spl_id     = azapi_resource.search_to_aiservices_spl.id
    account_id = azapi_resource.ai_account.id
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = 'Stop'
      $accountId = '${azapi_resource.ai_account.id}'
      $splName   = '${local.search_spl_name}'
      Write-Host "Looking for PE connection on $accountId matching SPL '$splName'..."
      for ($i = 1; $i -le 30; $i++) {
        $peName = az rest --method get `
          --uri "https://management.azure.com$accountId/privateEndpointConnections?api-version=2024-10-01" `
          --query "value[?starts_with(name, '$splName.')] | [0].name" -o tsv 2>$null
        if ($peName -and $peName -ne 'None') {
          $shortName = $peName.Split('/')[-1]
          $status = az rest --method get `
            --uri "https://management.azure.com$accountId/privateEndpointConnections/$shortName`?api-version=2024-10-01" `
            --query "properties.privateLinkServiceConnectionState.status" -o tsv
          Write-Host "Found PE connection '$shortName' with status '$status'"
          if ($status -eq 'Approved') { Write-Host "Already approved."; exit 0 }
          $body = '{"properties":{"privateLinkServiceConnectionState":{"status":"Approved","description":"Auto-approved by Terraform for Search SPL","actionsRequired":"None"}}}'
          $tmp = New-TemporaryFile
          $body | Out-File -FilePath $tmp -Encoding ascii
          az rest --method put `
            --uri "https://management.azure.com$accountId/privateEndpointConnections/$shortName`?api-version=2024-10-01" `
            --body "@$tmp"
          Remove-Item $tmp -Force
          Write-Host "Approval submitted."
          exit 0
        }
        Write-Host "Attempt $i`: PE connection not yet visible, sleeping 20s..."
        Start-Sleep -Seconds 20
      }
      Write-Error "PE connection for SPL '$splName' did not appear within timeout."
      exit 1
    EOT
  }

  depends_on = [azapi_resource.search_to_aiservices_spl]
}
