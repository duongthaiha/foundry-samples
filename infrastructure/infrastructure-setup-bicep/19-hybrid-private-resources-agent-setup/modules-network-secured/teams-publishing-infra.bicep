/*
Teams Publishing Infrastructure Module
----------------------------------------
Creates the infrastructure needed to publish a Foundry agent to Microsoft Teams
while keeping the agent on a private endpoint.

Architecture:
  Teams → Channel Adapter → Application Gateway (WAF v2, TLS)
    → APIM (JWT validation) → Foundry Agent Private Endpoint

Components:
  1. Application Gateway WAF v2 with custom domain + TLS
  2. APIM Bot messaging API with JWT validation policy
  3. Azure Bot Service linked to Application Gateway endpoint
  4. Teams Channel on the Bot Service
  5. Key Vault for TLS certificate storage

Reference: https://techcommunity.microsoft.com/blog/azure-ai-foundry-blog/
  foundry-agents-and-custom-engine-agents-through-the-corporate-firewall/4502218
*/

@description('Azure region')
param location string

@description('VNet name')
param vnetName string

@description('Address prefix for Application Gateway subnet')
param appGwSubnetPrefix string = '192.168.5.0/24'

@description('Name of the APIM service')
param apimName string

@description('Name of the AI Foundry account')
param accountName string

@description('Name of the project')
param projectName string

@description('Name of the published Agent Application')
param applicationName string

@description('Custom domain for the Bot messaging endpoint (e.g., agent.yourcompany.com)')
param customDomain string

@description('Key Vault name for TLS certificate')
param keyVaultName string = ''

@description('Name of the TLS certificate in Key Vault')
param tlsCertName string = 'teams-bot-tls'

@description('Bot Client ID (msaAppId) — the Agent Application identity client ID')
param botClientId string

@description('Bot Tenant ID')
param botTenantId string = ''

@description('APIM private endpoint IP address (use private IP instead of FQDN for private APIM)')
param apimPrivateIp string = ''

@description('Foundry Activity Protocol URL for the published application')
param activityProtocolUrl string

// Derived variables
var finalKeyVaultName = !empty(keyVaultName) ? keyVaultName : '${accountName}-kv'
var finalBotTenantId = !empty(botTenantId) ? botTenantId : tenant().tenantId
var botName = '${applicationName}-bot'
var appGwName = '${accountName}-appgw'
var appGwPipName = '${appGwName}-pip'

// ---- Application Gateway Subnet ----
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
}

resource appGwSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  name: 'appgw-subnet'
  parent: vnet
  properties: {
    addressPrefix: appGwSubnetPrefix
  }
}

// ---- Key Vault for TLS Certificate ----
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: finalKeyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

// ---- Application Gateway Public IP ----
resource appGwPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: appGwPipName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// ---- Self-signed TLS Certificate (placeholder for testing) ----
// In production, replace with a CA-issued certificate for your custom domain.
// Upload via: az keyvault certificate import --vault-name <kv> --name teams-bot-tls --file cert.pfx
resource certScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${finalKeyVaultName}-cert-script'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appGwIdentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '12.0'
    retentionInterval: 'PT1H'
    timeout: 'PT5M'
    environmentVariables: [
      { name: 'KV_NAME', value: finalKeyVaultName }
      { name: 'CERT_NAME', value: tlsCertName }
      { name: 'DOMAIN', value: customDomain }
    ]
    scriptContent: '''
      $ErrorActionPreference = 'Stop'
      $policy = New-AzKeyVaultCertificatePolicy -SubjectName "CN=$($env:DOMAIN)" -IssuerName Self -ValidityInMonths 12 -SecretContentType 'application/x-pkcs12'
      try {
        $existing = Get-AzKeyVaultCertificate -VaultName $env:KV_NAME -Name $env:CERT_NAME -ErrorAction SilentlyContinue
        if ($existing) {
          Write-Host "Certificate already exists, skipping creation"
        } else {
          Add-AzKeyVaultCertificate -VaultName $env:KV_NAME -Name $env:CERT_NAME -CertificatePolicy $policy
          Write-Host "Self-signed certificate created (placeholder — replace with CA cert for production)"
        }
      } catch {
        Write-Host "Certificate creation skipped: $_"
      }
      $DeploymentScriptOutputs = @{ certName = $env:CERT_NAME }
    '''
  }
  dependsOn: [
    keyVault
    appGwKvRole
  ]
}

// ---- WAF Policy ----
resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2024-05-01' = {
  name: '${appGwName}-waf-policy'
  location: location
  properties: {
    policySettings: {
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
      state: 'Enabled'
      mode: 'Prevention'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
        }
      ]
    }
  }
}

// ---- Application Gateway WAF v2 ----
resource appGwIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${appGwName}-identity'
  location: location
}

// Grant App Gateway identity Key Vault Secrets User role for TLS cert access
resource appGwKvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, appGwIdentity.id, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: keyVault
  properties: {
    principalId: appGwIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
  }
}

resource appGw 'Microsoft.Network/applicationGateways@2024-05-01' = {
  name: appGwName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appGwIdentity.id}': {}
    }
  }
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: 1
    }
    probes: [
      {
        name: 'apim-health-probe'
        properties: {
          protocol: 'Https'
          host: '${apimName}.azure-api.net'
          path: '/status-0123456789abcdef'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          match: {
            statusCodes: [ '200-404' ]
          }
        }
      }
    ]
    gatewayIPConfigurations: [
      {
        name: 'appGwIpConfig'
        properties: {
          subnet: {
            id: appGwSubnet.id
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          publicIPAddress: {
            id: appGwPip.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_443'
        properties: {
          port: 443
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'apim-backend'
        properties: {
          backendAddresses: [
            // Use APIM private IP if available, otherwise FQDN
            !empty(apimPrivateIp) ? {
              ipAddress: apimPrivateIp
            } : {
              fqdn: '${apimName}.azure-api.net'
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'apim-https-settings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 60
          hostName: '${apimName}.azure-api.net'
          pickHostNameFromBackendAddress: false
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', appGwName, 'apim-health-probe')
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'https-listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGwName, 'appGwPublicFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGwName, 'port_443')
          }
          protocol: 'Https'
          hostName: customDomain
          sslCertificate: {
            id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', appGwName, 'tls-cert')
          }
        }
      }
    ]
    sslCertificates: [
      {
        name: 'tls-cert'
        properties: {
          keyVaultSecretId: '${keyVault.properties.vaultUri}secrets/${tlsCertName}'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'bot-routing-rule'
        properties: {
          priority: 100
          ruleType: 'Basic'
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, 'https-listener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGwName, 'apim-backend')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGwName, 'apim-https-settings')
          }
        }
      }
    ]
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Prevention'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.2'
    }
    firewallPolicy: {
      id: wafPolicy.id
    }
  }
  dependsOn: [
    appGwKvRole
    certScript
  ]
}

// ---- APIM Bot Messaging API ----
resource apimService 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource botMessagingApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  name: 'bot-messaging'
  parent: apimService
  properties: {
    displayName: 'Bot Messaging Endpoint'
    path: 'bot'
    protocols: [ 'https' ]
    subscriptionRequired: false
    serviceUrl: activityProtocolUrl
  }
}

// Catch-all operation for Activity Protocol messages
resource botMessagingOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  name: 'forward-messages'
  parent: botMessagingApi
  properties: {
    displayName: 'Forward Bot Messages'
    method: 'POST'
    urlTemplate: '/*'
  }
}

// APIM policy: rewrite URI to append api-version, validate Bot JWT
resource botMessagingPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  name: 'policy'
  parent: botMessagingApi
  properties: {
    format: 'xml'
    value: '<policies><inbound><rewrite-uri template="/?api-version=2025-11-15-preview" copy-unmatched-params="false" /><validate-jwt header-name="Authorization" require-scheme="Bearer" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized - Invalid Bot token"><openid-config url="https://login.botframework.com/v1/.well-known/openidconfiguration" /><audiences><audience>${botClientId}</audience></audiences><issuers><issuer>https://api.botframework.com</issuer></issuers></validate-jwt><base /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
  }
}

// ---- Azure Bot Service ----
resource botService 'Microsoft.BotService/botServices@2023-09-15-preview' = {
  name: botName
  location: 'global'
  kind: 'azurebot'
  sku: {
    name: 'S1'
  }
  properties: {
    displayName: applicationName
    description: 'Foundry Agent published to Teams via private network'
    endpoint: 'https://${customDomain}/bot'
    msaAppId: botClientId
    msaAppTenantId: finalBotTenantId
    msaAppType: 'SingleTenant'
    publicNetworkAccess: 'Enabled'
  }
}

// ---- Teams Channel ----
resource teamsChannel 'Microsoft.BotService/botServices/channels@2023-09-15-preview' = {
  name: 'MsTeamsChannel'
  parent: botService
  location: 'global'
  properties: {
    channelName: 'MsTeamsChannel'
    properties: {
      acceptedTerms: true
      isEnabled: true
    }
  }
}

// ---- Outputs ----
output appGatewayPublicIp string = appGwPip.properties.ipAddress
output appGatewayName string = appGw.name
output botServiceName string = botService.name
output botEndpoint string = 'https://${customDomain}/bot'
output keyVaultName string = keyVault.name
output dnsInstruction string = 'Create DNS A record: ${customDomain} → ${appGwPip.properties.ipAddress}'
