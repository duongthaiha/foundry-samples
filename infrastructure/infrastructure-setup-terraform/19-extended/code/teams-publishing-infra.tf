# -----------------------------------------------------------------------------
# Teams Publishing Infrastructure (optional)
# Mirrors Bicep: modules-network-secured/teams-publishing-infra.bicep
#
# App Gateway WAF v2 + WAF Policy + Key Vault + Bot Service + Teams Channel
# Depends on the publish script for Activity Protocol URL + Bot Client ID.
# -----------------------------------------------------------------------------

locals {
  teams_enabled           = var.deploy_teams_publishing && local.apim_configured
  teams_effective_kv_name = var.teams_key_vault_name != "" ? var.teams_key_vault_name : "${local.account_name}-kv"
  teams_app_gw_name       = "${local.account_name}-appgw"
  teams_app_gw_pip_name   = "${local.teams_app_gw_name}-pip"
  teams_bot_name          = "${var.teams_application_name}-bot"
  teams_bot_tenant_id_eff = var.teams_bot_tenant_id != "" ? var.teams_bot_tenant_id : data.azurerm_client_config.current.tenant_id
  teams_backend_apim_host = "${local.apim_name}.azure-api.net"
}

# ---- App Gateway subnet -----------------------------------------------------
resource "azurerm_subnet" "app_gw" {
  count                = local.teams_enabled ? 1 : 0
  name                 = "appgw-subnet"
  resource_group_name  = local.existing_vnet_passed_in ? local.vnet_rg : azurerm_resource_group.rg.name
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.app_gw_subnet_prefix]

  depends_on = [azurerm_virtual_network.vnet]
}

# ---- Key Vault for TLS certificate ------------------------------------------
resource "azurerm_key_vault" "teams" {
  count                      = local.teams_enabled ? 1 : 0
  name                       = local.teams_effective_kv_name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
}

# ---- App Gateway public IP --------------------------------------------------
resource "azurerm_public_ip" "app_gw" {
  count               = local.teams_enabled ? 1 : 0
  name                = local.teams_app_gw_pip_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  allocation_method   = "Static"
}

# ---- App Gateway managed identity ------------------------------------------
resource "azurerm_user_assigned_identity" "app_gw" {
  count               = local.teams_enabled ? 1 : 0
  name                = "${local.teams_app_gw_name}-identity"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_role_assignment" "app_gw_kv_secrets" {
  count = local.teams_enabled ? 1 : 0
  scope = azurerm_key_vault.teams[0].id
  # Key Vault Secrets User
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6"
  principal_id       = azurerm_user_assigned_identity.app_gw[0].principal_id
  principal_type     = "ServicePrincipal"
}

# ---- Self-signed TLS certificate creation script ---------------------------
resource "azapi_resource" "teams_cert_script" {
  count                     = local.teams_enabled ? 1 : 0
  type                      = "Microsoft.Resources/deploymentScripts@2023-08-01"
  name                      = "${local.teams_effective_kv_name}-cert-script"
  parent_id                 = azurerm_resource_group.rg.id
  location                  = var.location
  schema_validation_enabled = false

  body = {
    kind = "AzurePowerShell"
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        (azurerm_user_assigned_identity.app_gw[0].id) = {}
      }
    }
    properties = {
      azPowerShellVersion = "12.0"
      retentionInterval   = "PT1H"
      timeout             = "PT5M"
      environmentVariables = [
        { name = "KV_NAME", value = local.teams_effective_kv_name },
        { name = "CERT_NAME", value = var.teams_tls_cert_name },
        { name = "DOMAIN", value = var.teams_custom_domain },
      ]
      scriptContent = <<-EOT
        $ErrorActionPreference = 'Stop'
        $policy = New-AzKeyVaultCertificatePolicy -SubjectName "CN=$($env:DOMAIN)" -IssuerName Self -ValidityInMonths 12 -SecretContentType 'application/x-pkcs12'
        try {
          $existing = Get-AzKeyVaultCertificate -VaultName $env:KV_NAME -Name $env:CERT_NAME -ErrorAction SilentlyContinue
          if ($existing) {
            Write-Host "Certificate already exists, skipping creation"
          } else {
            Add-AzKeyVaultCertificate -VaultName $env:KV_NAME -Name $env:CERT_NAME -CertificatePolicy $policy
            Write-Host "Self-signed certificate created (placeholder - replace with CA cert for production)"
          }
        } catch {
          Write-Host "Certificate creation skipped: $_"
        }
        $DeploymentScriptOutputs = @{ certName = $env:CERT_NAME }
      EOT
    }
  }

  depends_on = [azurerm_role_assignment.app_gw_kv_secrets]
}

# ---- WAF Policy -------------------------------------------------------------
resource "azurerm_web_application_firewall_policy" "teams" {
  count               = local.teams_enabled ? 1 : 0
  name                = "${local.teams_app_gw_name}-waf-policy"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb     = 100
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
}

# ---- Application Gateway WAF v2 --------------------------------------------
resource "azurerm_application_gateway" "teams" {
  count               = local.teams_enabled ? 1 : 0
  name                = local.teams_app_gw_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  firewall_policy_id = azurerm_web_application_firewall_policy.teams[0].id

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app_gw[0].id]
  }

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "appGwIpConfig"
    subnet_id = azurerm_subnet.app_gw[0].id
  }

  frontend_port {
    name = "port_443"
    port = 443
  }

  frontend_ip_configuration {
    name                 = "appGwPublicFrontendIp"
    public_ip_address_id = azurerm_public_ip.app_gw[0].id
  }

  backend_address_pool {
    name         = "apim-backend"
    fqdns        = var.teams_apim_private_ip == "" ? [local.teams_backend_apim_host] : null
    ip_addresses = var.teams_apim_private_ip != "" ? [var.teams_apim_private_ip] : null
  }

  probe {
    name                = "apim-health-probe"
    protocol            = "Https"
    host                = local.teams_backend_apim_host
    path                = "/status-0123456789abcdef"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    match {
      status_code = ["200-404"]
    }
  }

  backend_http_settings {
    name                                = "apim-https-settings"
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 60
    host_name                           = local.teams_backend_apim_host
    pick_host_name_from_backend_address = false
    probe_name                          = "apim-health-probe"
  }

  ssl_certificate {
    name                = "tls-cert"
    key_vault_secret_id = "${azurerm_key_vault.teams[0].vault_uri}secrets/${var.teams_tls_cert_name}"
  }

  http_listener {
    name                           = "https-listener"
    frontend_ip_configuration_name = "appGwPublicFrontendIp"
    frontend_port_name             = "port_443"
    protocol                       = "Https"
    host_name                      = var.teams_custom_domain
    ssl_certificate_name           = "tls-cert"
  }

  request_routing_rule {
    name                       = "bot-routing-rule"
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = "https-listener"
    backend_address_pool_name  = "apim-backend"
    backend_http_settings_name = "apim-https-settings"
  }

  waf_configuration {
    enabled          = true
    firewall_mode    = "Prevention"
    rule_set_type    = "OWASP"
    rule_set_version = "3.2"
  }

  depends_on = [
    azurerm_role_assignment.app_gw_kv_secrets,
    azapi_resource.teams_cert_script,
  ]
}

# ---- APIM Bot Messaging API -------------------------------------------------
resource "azurerm_api_management_api" "bot_messaging" {
  count                 = local.teams_enabled ? 1 : 0
  name                  = "bot-messaging"
  resource_group_name   = local.apim_passed_in ? local.apim_parts[4] : azurerm_resource_group.rg.name
  api_management_name   = local.apim_name
  revision              = "1"
  display_name          = "Bot Messaging Endpoint"
  path                  = "bot"
  protocols             = ["https"]
  subscription_required = false
  service_url           = local.teams_activity_protocol_url_effective
}

resource "azurerm_api_management_api_operation" "bot_forward" {
  count               = local.teams_enabled ? 1 : 0
  operation_id        = "forward-messages"
  api_name            = azurerm_api_management_api.bot_messaging[0].name
  api_management_name = local.apim_name
  resource_group_name = local.apim_passed_in ? local.apim_parts[4] : azurerm_resource_group.rg.name
  display_name        = "Forward Bot Messages"
  method              = "POST"
  url_template        = "/*"
}

resource "azurerm_api_management_api_policy" "bot_messaging" {
  count               = local.teams_enabled ? 1 : 0
  api_name            = azurerm_api_management_api.bot_messaging[0].name
  api_management_name = local.apim_name
  resource_group_name = local.apim_passed_in ? local.apim_parts[4] : azurerm_resource_group.rg.name

  xml_content = format("<policies><inbound><rewrite-uri template=\"/?api-version=2025-11-15-preview\" copy-unmatched-params=\"false\" /><validate-jwt header-name=\"Authorization\" require-scheme=\"Bearer\" failed-validation-httpcode=\"401\" failed-validation-error-message=\"Unauthorized - Invalid Bot token\"><openid-config url=\"https://login.botframework.com/v1/.well-known/openidconfiguration\" /><audiences><audience>%s</audience></audiences><issuers><issuer>https://api.botframework.com</issuer></issuers></validate-jwt><base /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>", local.teams_bot_client_id_effective)
}

# ---- Azure Bot Service ------------------------------------------------------
resource "azurerm_bot_service_azure_bot" "teams" {
  count                         = local.teams_enabled ? 1 : 0
  name                          = local.teams_bot_name
  location                      = "global"
  resource_group_name           = azurerm_resource_group.rg.name
  sku                           = "S1"
  microsoft_app_id              = local.teams_bot_client_id_effective
  microsoft_app_type            = "SingleTenant"
  microsoft_app_tenant_id       = local.teams_bot_tenant_id_eff
  endpoint                      = "https://${var.teams_custom_domain}/bot"
  display_name                  = var.teams_application_name
  public_network_access_enabled = true
}

resource "azurerm_bot_channel_ms_teams" "teams" {
  count               = local.teams_enabled ? 1 : 0
  bot_name            = azurerm_bot_service_azure_bot.teams[0].name
  location            = azurerm_bot_service_azure_bot.teams[0].location
  resource_group_name = azurerm_resource_group.rg.name
}
