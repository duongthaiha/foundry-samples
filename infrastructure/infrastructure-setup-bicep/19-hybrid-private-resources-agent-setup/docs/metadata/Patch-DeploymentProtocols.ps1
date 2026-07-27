<#
.SYNOPSIS
  Re-register a Foundry Agent Managed Deployment with both Responses and
  Activity protocols. Idempotent.

.DESCRIPTION
  The Responses-API metadata cap (16 top-level keys) is tripped on every
  Teams turn if the Managed Deployment lacks the Activity protocol entry
  — the bridge then falls back to a generic serializer that flattens the
  whole Bot Framework Activity envelope into the Responses metadata
  object (17+ keys).

  This script GETs the current deployment, preserves agents[],
  displayName, and deploymentType, and PUTs it back with:

    protocols = [
      { protocol = "Responses", version = "1.0" },
      { protocol = "Activity",  version = "1.0" }
    ]

  Use -WhatIf to preview without modifying anything.

.PARAMETER SubscriptionId
.PARAMETER ResourceGroup
.PARAMETER Account
.PARAMETER Project
.PARAMETER Application
.PARAMETER Deployment

.EXAMPLE
  ./Patch-DeploymentProtocols.ps1 `
    -SubscriptionId 6372dff5-b3ec-4613-bd5d-26767f57b729 `
    -ResourceGroup  rg-foundry-uk-public `
    -Account        foundry-hd-uk-public `
    -Project        proj-default `
    -Application    sample-agent `
    -Deployment     sample-agent

.NOTES
  Control-plane API; works from any machine with az login.
  Required role on the project: AI Foundry Contributor (or equivalent).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter(Mandatory = $true)][string]$SubscriptionId,
  [Parameter(Mandatory = $true)][string]$ResourceGroup,
  [Parameter(Mandatory = $true)][string]$Account,
  [Parameter(Mandatory = $true)][string]$Project,
  [Parameter(Mandatory = $true)][string]$Application,
  [Parameter(Mandatory = $true)][string]$Deployment
)

$ErrorActionPreference = "Stop"

$tok = (az account get-access-token --resource "https://management.azure.com" --query accessToken -o tsv)
if ([string]::IsNullOrEmpty($tok)) { throw "Failed to acquire ARM token. Run 'az login' first." }
$h       = @{ Authorization = "Bearer $tok"; "Content-Type" = "application/json" }
$armBase = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$Account/projects/$Project"
$uri     = "$armBase/applications/$Application/agentDeployments/$Deployment`?api-version=2026-01-15-preview"

$current = Invoke-RestMethod $uri -Headers @{ Authorization = "Bearer $tok" }

Write-Host "=== Current protocols on $Deployment ==="
$current.properties.protocols | ConvertTo-Json

$hasResponses = $current.properties.protocols | Where-Object { $_.protocol -eq "Responses" }
$hasActivity  = $current.properties.protocols | Where-Object { $_.protocol -eq "Activity"  }
if ($hasResponses -and $hasActivity) {
  Write-Host ""
  Write-Host "Both Responses and Activity protocols already registered. Nothing to do."
  return
}

$body = @{
  properties = @{
    displayName    = $current.properties.displayName
    deploymentType = $current.properties.deploymentType
    protocols      = @(
      @{ protocol = "Responses"; version = "1.0" }
      @{ protocol = "Activity";  version = "1.0" }
    )
    agents = $current.properties.agents
  }
} | ConvertTo-Json -Depth 8

Write-Host ""
Write-Host "=== Proposed PUT body ==="
$body

if ($PSCmdlet.ShouldProcess("$Application/$Deployment", "PUT protocols [Responses, Activity]")) {
  $result = Invoke-RestMethod $uri -Method Put -Headers $h -Body $body
  Write-Host ""
  Write-Host "=== After PUT ==="
  Write-Host ("provisioningState : {0}" -f $result.properties.provisioningState)
  Write-Host ("state             : {0}" -f $result.properties.state)
  $result.properties.protocols | ConvertTo-Json
  Write-Host ""
  Write-Host "Done. Send a message from Teams to verify."
}
