#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Obtains a Let's Encrypt TLS certificate via DNS-01 challenge and imports it to Azure Key Vault.

.DESCRIPTION
    This script uses certbot in manual DNS-01 mode to obtain a free TLS certificate from Let's Encrypt.
    It guides you through creating the required DNS TXT record at your registrar (e.g., IONOS),
    then imports the certificate as PFX to Azure Key Vault for use by Application Gateway.

.PARAMETER Domain
    The domain to obtain a certificate for (e.g., agent.belugaconsultant.co.uk)

.PARAMETER KeyVaultName
    The Azure Key Vault name to import the certificate to

.PARAMETER CertName
    The certificate name in Key Vault (default: teams-bot-tls)

.PARAMETER Email
    Email address for Let's Encrypt notifications

.EXAMPLE
    ./obtain-letsencrypt-cert.ps1 -Domain "agent.belugaconsultant.co.uk" -KeyVaultName "aiservicescdpy-kv" -Email "admin@belugaconsultant.co.uk"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Domain = "agent.belugaconsultant.co.uk",

    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory=$false)]
    [string]$CertName = "teams-bot-tls",

    [Parameter(Mandatory=$true)]
    [string]$Email
)

$ErrorActionPreference = 'Stop'

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Let's Encrypt Certificate Obtainer for Azure Key Vault" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Domain:     $Domain"
Write-Host "Key Vault:  $KeyVaultName"
Write-Host "Cert Name:  $CertName"
Write-Host "Email:      $Email"
Write-Host ""

# Check certbot is installed
if (-not (Get-Command certbot -ErrorAction SilentlyContinue)) {
    Write-Host "certbot is not installed. Installing via pip..." -ForegroundColor Yellow
    pip install certbot --quiet
    if (-not (Get-Command certbot -ErrorAction SilentlyContinue)) {
        Write-Error "Failed to install certbot. Please install manually: pip install certbot"
        exit 1
    }
}

# Create a temp directory for certbot
$certDir = Join-Path $env:TEMP "letsencrypt-$Domain"
if (-not (Test-Path $certDir)) { New-Item -ItemType Directory -Path $certDir -Force | Out-Null }

Write-Host ""
Write-Host "Step 1: Requesting certificate from Let's Encrypt..." -ForegroundColor Green
Write-Host "        Using DNS-01 challenge (manual mode)" -ForegroundColor Gray
Write-Host ""
Write-Host "  IMPORTANT: When certbot asks you to create a TXT record," -ForegroundColor Yellow
Write-Host "  go to your IONOS DNS management and create:" -ForegroundColor Yellow
Write-Host ""
Write-Host "    Record Type: TXT" -ForegroundColor White
Write-Host "    Host:        _acme-challenge.agent" -ForegroundColor White
Write-Host "    Value:       (certbot will tell you)" -ForegroundColor White
Write-Host "    TTL:         300" -ForegroundColor White
Write-Host ""
Write-Host "  After creating the record, wait ~2 minutes for DNS propagation" -ForegroundColor Yellow
Write-Host "  then press Enter in certbot to continue." -ForegroundColor Yellow
Write-Host ""

# Run certbot in manual DNS-01 mode
certbot certonly `
    --manual `
    --preferred-challenges dns `
    --agree-tos `
    --no-eff-email `
    --email $Email `
    -d $Domain `
    --config-dir "$certDir/config" `
    --work-dir "$certDir/work" `
    --logs-dir "$certDir/logs" `
    --manual-public-ip-logging-ok

if ($LASTEXITCODE -ne 0) {
    Write-Error "certbot failed. Check the output above for details."
    exit 1
}

Write-Host ""
Write-Host "Step 2: Converting certificate to PFX format..." -ForegroundColor Green

# Find the cert files
$certPath = Join-Path $certDir "config/live/$Domain"
$fullchain = Join-Path $certPath "fullchain.pem"
$privkey = Join-Path $certPath "privkey.pem"

if (-not (Test-Path $fullchain) -or -not (Test-Path $privkey)) {
    Write-Error "Certificate files not found at $certPath"
    exit 1
}

# Convert to PFX using openssl
$pfxPath = Join-Path $certDir "certificate.pfx"
$pfxPassword = [System.Guid]::NewGuid().ToString().Substring(0, 16)

openssl pkcs12 -export -out $pfxPath -in $fullchain -inkey $privkey -password "pass:$pfxPassword"

if (-not (Test-Path $pfxPath)) {
    Write-Error "Failed to create PFX file"
    exit 1
}

Write-Host "  PFX created at: $pfxPath" -ForegroundColor Gray

Write-Host ""
Write-Host "Step 3: Importing certificate to Azure Key Vault..." -ForegroundColor Green

az keyvault certificate import `
    --vault-name $KeyVaultName `
    --name $CertName `
    --file $pfxPath `
    --password $pfxPassword `
    --query "{name:name, expires:attributes.expires}" -o json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to import certificate to Key Vault"
    exit 1
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " SUCCESS!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Certificate for $Domain imported to Key Vault: $KeyVaultName"
Write-Host "Certificate name: $CertName"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Application Gateway will automatically pick up the new cert"
Write-Host "  2. Ensure DNS A record exists: $Domain -> <App Gateway IP>"
Write-Host "  3. You can delete the _acme-challenge TXT record from IONOS"
Write-Host "  4. Certificate expires in 90 days — re-run this script to renew"
Write-Host ""

# Cleanup
Remove-Item -Recurse -Force $certDir -ErrorAction SilentlyContinue
