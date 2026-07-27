<#
.SYNOPSIS
  Publish a new version of a Foundry agent with a trimmed Layer-2
  metadata object.

.DESCRIPTION
  Use when Get-AgentMetadataAudit.ps1 shows the agent author has put
  too many keys on agent.metadata, leaving no headroom for the Teams
  bridge under the 16-key Responses-API cap.

  Agent versions are immutable; this script reads the latest version
  and publishes a NEW version with only the keys you opt-in via -Keep.

.PARAMETER Account
.PARAMETER Project
.PARAMETER Agent
.PARAMETER Keep
  Array of metadata keys to retain. Recommended: pick at most 8 so the
  bridge has 8 keys of headroom.

.EXAMPLE
  ./Set-AgentMetadata.ps1 -Account foundry-hd-uk-public -Project proj-default -Agent sample-agent -Keep @('logo','env')

.NOTES
  Data-plane API; must reach the Foundry FQDN
  (jumpbox/VPN for private accounts).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter(Mandatory = $true)][string]$Account,
  [Parameter(Mandatory = $true)][string]$Project,
  [Parameter(Mandatory = $true)][string]$Agent,
  [string[]]$Keep = @()
)

$ErrorActionPreference = "Stop"

$tok  = (az account get-access-token --resource "https://ai.azure.com" --query accessToken -o tsv)
if ([string]::IsNullOrEmpty($tok)) { throw "Failed to acquire ai.azure.com token. Run 'az login' first." }
$hdr  = @{ Authorization = "Bearer $tok"; "Content-Type" = "application/json" }
$base = "https://$Account.services.ai.azure.com/api/projects/$Project"

$versions = Invoke-RestMethod "$base/agents/$Agent/versions?api-version=v1" -Headers $hdr
$current  = $versions.data[0]
Write-Host "Current latest version: $($current.version)"
Write-Host "Current metadata keys : $(@($current.metadata.PSObject.Properties.Name) -join ', ')"

$trimmed = @{}
foreach ($k in $Keep) {
  if ($current.metadata.$k) {
    $trimmed[$k] = $current.metadata.$k
  } else {
    Write-Warning "Key '$k' not present in current metadata. Skipping."
  }
}

Write-Host ""
Write-Host "Trimmed metadata ($($trimmed.Count) keys):"
$trimmed | ConvertTo-Json

if ($trimmed.Count -gt 8) {
  Write-Warning "Keeping more than 8 keys leaves little headroom for the Teams bridge. Consider trimming further."
}

$body = $current | Select-Object -Property * -ExcludeProperty version, created_at, modified_at, id, object, agent_guid, status
$body.metadata = $trimmed
$bodyJson = $body | ConvertTo-Json -Depth 30

if ($PSCmdlet.ShouldProcess("$Agent", "POST new version with trimmed metadata")) {
  $new = Invoke-RestMethod "$base/agents/$Agent/versions?api-version=v1" -Method Post -Headers $hdr -Body $bodyJson
  Write-Host ""
  Write-Host "Published new version: $($new.version)"
  Write-Host "Remember to update the Managed Deployment's agents[].agentVersion to this value if not pinned to 'latest'."
}
