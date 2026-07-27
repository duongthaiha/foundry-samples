<#
.SYNOPSIS
  GET the Agent Application(s) and Managed Deployment(s) on a Foundry project.

.DESCRIPTION
  Surfaces the registered protocols on each agent deployment so you can
  confirm whether 'Activity' is missing (the typical root cause of
  Responses-API metadata cap failures on Teams turns).

.PARAMETER SubscriptionId
.PARAMETER ResourceGroup
.PARAMETER Account
.PARAMETER Project
.PARAMETER Application
  Optional. If omitted, all applications under the project are listed.

.EXAMPLE
  ./Get-ApplicationDeployment.ps1 -SubscriptionId 6372dff5-... -ResourceGroup rg-foundry-uk-public -Account foundry-hd-uk-public -Project proj-default

.NOTES
  Control-plane API; works from any machine with az login.
#>
param(
  [Parameter(Mandatory = $true)][string]$SubscriptionId,
  [Parameter(Mandatory = $true)][string]$ResourceGroup,
  [Parameter(Mandatory = $true)][string]$Account,
  [Parameter(Mandatory = $true)][string]$Project,
  [string]$Application = ""
)

$ErrorActionPreference = "Stop"

$tok = (az account get-access-token --resource "https://management.azure.com" --query accessToken -o tsv)
if ([string]::IsNullOrEmpty($tok)) { throw "Failed to acquire ARM token. Run 'az login' first." }
$h   = @{ Authorization = "Bearer $tok" }
$armBase = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$Account/projects/$Project"

if ([string]::IsNullOrEmpty($Application)) {
  $apps = (Invoke-RestMethod "$armBase/applications?api-version=2026-01-15-preview" -Headers $h).value
} else {
  $apps = @( Invoke-RestMethod "$armBase/applications/$Application`?api-version=2026-01-15-preview" -Headers $h )
}

foreach ($app in $apps) {
  Write-Host ""
  Write-Host "=== Application: $($app.name) ==="
  $app.properties | Select-Object displayName, applicationId, baseUrl, isEnabled, provisioningState, @{n='authzScheme';e={$_.authorizationPolicy.authorizationScheme}} | Format-List

  $deps = (Invoke-RestMethod "$armBase/applications/$($app.name)/agentDeployments?api-version=2026-01-15-preview" -Headers $h).value
  foreach ($dep in $deps) {
    Write-Host "--- Deployment: $($dep.name) ---"
    $protocols = $dep.properties.protocols | ForEach-Object { "$($_.protocol)/$($_.version)" }
    Write-Host ("  protocols       : {0}" -f ($protocols -join ", "))
    Write-Host ("  deploymentType  : {0}" -f $dep.properties.deploymentType)
    Write-Host ("  state           : {0}" -f $dep.properties.state)
    Write-Host ("  provisioning    : {0}" -f $dep.properties.provisioningState)
    Write-Host ("  agents          :")
    foreach ($a in $dep.properties.agents) {
      Write-Host ("    - name={0}, version={1}" -f $a.agentName, $a.agentVersion)
    }

    $hasResponses = $protocols -match '^Responses/'
    $hasActivity  = $protocols -match '^Activity/'
    if (-not $hasActivity) {
      Write-Warning "Activity protocol is NOT registered on deployment '$($dep.name)'."
      Write-Warning "This is the typical root cause of the Teams 'object_above_max_properties' on metadata."
      Write-Warning "Run Patch-DeploymentProtocols.ps1 to fix."
    } elseif (-not $hasResponses) {
      Write-Warning "Responses protocol is NOT registered on deployment '$($dep.name)'. Run Patch-DeploymentProtocols.ps1."
    } else {
      Write-Host "  OK: both Responses and Activity protocols are registered."
    }
  }
}
