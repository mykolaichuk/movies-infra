# Layered state: the stack reads what bootstrap created from bootstrap's own
# state file instead of copying IDs around by hand.
data "terraform_remote_state" "bootstrap" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.tfstate_resource_group
    storage_account_name = var.tfstate_storage_account
    container_name       = "tfstate"
    key                  = "bootstrap.tfstate"
    use_azuread_auth     = true
    use_msi              = true
  }
}

data "azurerm_client_config" "current" {}

# The resource group was created empty by bootstrap; the agent's rights are
# scoped to it.
data "azurerm_resource_group" "app" {
  name = local.bootstrap.resource_groups.app
}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

locals {
  bootstrap = data.terraform_remote_state.bootstrap.outputs

  name     = var.prefix
  location = data.azurerm_resource_group.app.location
  rg       = data.azurerm_resource_group.app.name

  # Object ID of the identity running Terraform = the agent's managed identity.
  agent_principal_id = data.azurerm_client_config.current.object_id
  tenant_id          = data.azurerm_client_config.current.tenant_id

  tags = merge({
    project    = var.prefix
    managed-by = "terraform"
    layer      = "stack"
    repo       = "movies-infra"
  }, var.tags)

  spoke_subnets = {
    app               = cidrsubnet(var.spoke_address_space, 8, 1) # 10.20.1.0/24
    private_endpoints = cidrsubnet(var.spoke_address_space, 8, 2) # 10.20.2.0/24
  }
}
