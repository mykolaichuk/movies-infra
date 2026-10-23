# The stack runs only on the self-hosted agent. Every provider authenticates
# with the agent's user-assigned managed identity; the agent environment
# (bootstrap cloud-init) sets ARM_USE_MSI, ARM_CLIENT_ID, ARM_TENANT_ID and
# ARM_SUBSCRIPTION_ID. No secrets in code, variables or pipeline settings.

provider "azurerm" {
  # Shared keys are disabled on every storage account: data plane via Entra ID.
  storage_use_azuread = true

  # Resource providers were registered by bootstrap; the agent has no
  # subscription-level rights to register them itself.
  resource_provider_registrations = "none"

  features {
    key_vault {
      # Demo: keep soft-deleted vaults on destroy so a re-apply can recover them.
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azuread" {}
