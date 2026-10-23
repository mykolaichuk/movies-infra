# Bootstrap runs once from Azure Cloud Shell under the subscription Owner's
# identity (Azure CLI auth). Everything after it runs on the self-hosted agent.

provider "azurerm" {
  subscription_id = var.subscription_id

  # The state storage account has shared keys disabled, so all data-plane
  # calls (containers, blobs) must use Entra ID tokens.
  storage_use_azuread = true

  # azurerm 5.x registers nothing by default. Bootstrap registers every
  # resource provider the whole project needs, because the agent identity
  # used later has no subscription-level rights to do it itself.
  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.AlertsManagement",
    "Microsoft.Compute",
    "Microsoft.Dashboard",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.Sql",
    "Microsoft.Storage",
  ]

  features {}
}

provider "azuread" {}

# The same short-lived PAT registers the agent (see agent.tf).
# Pass it as TF_VAR_azdo_pat and revoke it once bootstrap is done.
provider "azuredevops" {
  org_service_url       = var.azdo_org_url
  personal_access_token = var.azdo_pat
}
