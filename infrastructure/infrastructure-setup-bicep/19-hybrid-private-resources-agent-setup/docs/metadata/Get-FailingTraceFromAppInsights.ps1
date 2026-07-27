<#
.SYNOPSIS
  Pull failing Foundry agent turns from Application Insights using the
  ms-cv correlation header.

.DESCRIPTION
  Useful when a customer reports an 'object_above_max_properties' error
  and gives you their ms-cv / activityId / ConversationId. Only works if
  the Bot Service is wired to Application Insights via
  developerAppInsightsApplicationId (or if a custom Teams bot is
  emitting traces to App Insights).

.PARAMETER ResourceGroup
.PARAMETER AppInsightsName
.PARAMETER MsCv
  The ms-cv value (or its prefix) from the failure toast / customer
  report.
.PARAMETER LookbackDays
  How far back to search. Default 2.

.EXAMPLE
  ./Get-FailingTraceFromAppInsights.ps1 `
    -ResourceGroup rg-foundry-uk-public `
    -AppInsightsName airgfoundryukpublic6372df `
    -MsCv "x8zO/RASTkOO4R3CcyRszg"

.NOTES
  Requires the application-insights extension:
    az extension add --name application-insights
#>
param(
  [Parameter(Mandatory = $true)][string]$ResourceGroup,
  [Parameter(Mandatory = $true)][string]$AppInsightsName,
  [Parameter(Mandatory = $true)][string]$MsCv,
  [int]$LookbackDays = 2
)

$ErrorActionPreference = "Stop"

$kql = @"
let cv = '$MsCv';
union requests, dependencies, traces, exceptions
| where timestamp > ago(${LookbackDays}d)
| where operation_Id startswith cv
   or tostring(customDimensions['ms-cv']) startswith cv
   or tostring(customDimensions.['MS-CV']) startswith cv
   or tostring(message) has cv
| project timestamp, itemType, name, resultCode,
          operation_Id, parentId=operation_ParentId,
          message=tostring(message), cd=tostring(customDimensions)
| order by timestamp asc
"@

$outFile = "failing-trace-$(($MsCv -replace '[^a-zA-Z0-9]','_')).json"
$result = az monitor app-insights query --app $AppInsightsName -g $ResourceGroup --analytics-query $kql -o json
$result | Out-File $outFile -Encoding utf8
Write-Host "Wrote $outFile"

$json = $result | ConvertFrom-Json
$rows = $json.tables[0].rows
if (-not $rows -or $rows.Count -eq 0) {
  Write-Warning "No rows found for ms-cv prefix '$MsCv' in the last $LookbackDays days."
  Write-Warning "If the Bot Service's developerAppInsightsApplicationId is null, traces will not appear here."
  return
}

Write-Host "Found $($rows.Count) row(s):"
foreach ($r in $rows) {
  Write-Host ("  [{0}] {1} {2} {3}" -f $r[0], $r[1], $r[2], $r[3])
}
Write-Host ""
Write-Host "Inspect $outFile for full payloads — look for the /responses call body and enumerate top-level metadata keys."
