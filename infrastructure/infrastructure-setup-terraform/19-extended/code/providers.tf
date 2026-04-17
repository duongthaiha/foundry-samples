provider "azapi" {}

provider "azurerm" {
  features {}
  storage_use_azuread = true
  # If var.subscription_id is null, the provider falls back to the CLI / env context.
  subscription_id = var.subscription_id
}
