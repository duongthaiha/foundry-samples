<#
.SYNOPSIS
  Audits the Layer-2 (author-supplied) metadata of a Foundry agent.

.DESCRIPTION
  Pulls the latest (or specified) version of an agent from the Foundry data
  plane and counts top-level metadata keys at every location an author can
  set them: agent root, each tool, each workflow step, plus any
  additional_metadata defaults.

  Helps determine whether the agent itself is contributing to a
  Responses-API "object_above_max_properties" failure (cap = 16 top-level
  keys on the merged metadata object).

  Run from a machine that can reach the Foundry account FQDN:
    - Public account: any machine with `az login`.
    - Private account: a jumpbox or VPN-connected machine in the VNet that
      hosts the private endpoint.

.PARAMETER Account
  Foundry / AI Services account name.

.PARAMETER Project
  Project name inside the account.

.PARAMETER Agent
  Agent name.

.PARAMETER Version
  Agent version. Empty (default) = latest.

.EXAMPLE
  ./Get-AgentMetadataAudit.ps1 -Account foundry-hd-uk-public -Project proj-default -Agent sample-agent

.NOTES
  Reference for the cap and bridge contribution:
    ./README.md in this folder.
#>
param(
  [Parameter(Mandatory = $true)][string]$Account,
  [Parameter(Mandatory = $true)][string]$Project,
  [Parameter(Mandatory = $true)][string]$Agent,
  [string]$Version = ""
)

$ErrorActionPreference = "Stop"

$tok  = (az account get-access-token --resource "https://ai.azure.com" --query accessToken -o tsv)
if ([string]::IsNullOrEmpty($tok)) { throw "Failed to acquire ai.azure.com token. Run 'az login' first." }
$hdr  = @{ Authorization = "Bearer $tok" }
$base = "https://$Account.services.ai.azure.com/api/projects/$Project"

if ([string]::IsNullOrEmpty($Version)) {
  $versions = Invoke-RestMethod "$base/agents/$Agent/versions?api-version=v1" -Headers $hdr
  $Version  = $versions.data[0].version
  Write-Host "Latest version: $Version"
}

$def = Invoke-RestMethod "$base/agents/$Agent/versions/$Version`?api-version=v1" -Headers $hdr

$dumpFile = "agent-$Agent-$Version.json"
$def | ConvertTo-Json -Depth 30 | Out-File $dumpFile -Encoding utf8
Write-Host "Wrote full agent definition to $dumpFile"
Write-Host ""

function Show-MetadataKeys {
  param($Obj, [string]$Label)
  if ($null -ne $Obj.metadata) {
    $keys = @($Obj.metadata.PSObject.Properties.Name)
    Write-Host ("[{0}] metadata keys = {1}" -f $Label, $keys.Count)
    $keys | ForEach-Object { Write-Host ("    - {0}" -f $_) }
  }
}

Write-Host "=== Layer 2 audit (author-supplied metadata) ==="
Show-MetadataKeys -Obj $def -Label "agent.root"
if ($def.tools) {
  for ($i = 0; $i -lt $def.tools.Count; $i++) {
    Show-MetadataKeys -Obj $def.tools[$i] -Label "tools[$i] ($($def.tools[$i].type))"
  }
}
if ($def.workflow -and $def.workflow.steps) {
  for ($i = 0; $i -lt $def.workflow.steps.Count; $i++) {
    Show-MetadataKeys -Obj $def.workflow.steps[$i] -Label "workflow.steps[$i]"
  }
}
if ($def.additional_metadata) {
  Show-MetadataKeys -Obj $def -Label "agent.additional_metadata-as-defaults"
}

$authorCount = if ($def.metadata) { @($def.metadata.PSObject.Properties.Name).Count } else { 0 }

Write-Host ""
Write-Host "=== Bridge contribution estimate (Layer 1) ==="
$teamsBridgeKeys = @(
  "channel","conversationId","activityId","tenantId","aadObjectId",
  "serviceUrl","locale","recipientId","fromId",
  "teamId","channelId","channelDataTenantId","meetingId","botId","replyToId"
)
Write-Host "Teams Activity-Protocol fallback (no Activity protocol registered) typically adds ~$($teamsBridgeKeys.Count) keys:"
$teamsBridgeKeys | ForEach-Object { Write-Host "    + $_" }

Write-Host ""
Write-Host "=========================================================="
Write-Host "Author metadata on agent root: $authorCount"
Write-Host "Responses-API cap on merged metadata: 16 top-level keys"
Write-Host "Headroom for bridge contribution: $([Math]::Max(0, 16 - $authorCount))"
Write-Host ""
Write-Host "If headroom < observed bridge contribution -> failure."
Write-Host "First fix to try: ensure the Managed Deployment registers"
Write-Host "both 'Responses' and 'Activity' protocols. See"
Write-Host "Get-ApplicationDeployment.ps1 and Patch-DeploymentProtocols.ps1."
Write-Host "=========================================================="
