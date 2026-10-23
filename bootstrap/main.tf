data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

locals {
  name = var.prefix

  tags = merge({
    project    = var.prefix
    managed-by = "terraform"
    layer      = "bootstrap"
    repo       = "movies-infra"
  }, var.tags)

  # Hub subnets. The spoke lives in the stack layer.
  hub_subnets = {
    agents            = cidrsubnet(var.hub_address_space, 8, 1) # 10.10.1.0/24
    private_endpoints = cidrsubnet(var.hub_address_space, 8, 2) # 10.10.2.0/24
  }
}

# Three resource groups = three blast radii.
#   mgmt: hub VNet, build agent, Terraform state (management plane)
#   dns:  private DNS zones shared by hub and spoke
#   app:  everything the workload needs; created empty here so the agent
#         identity can be scoped to it before the stack layer exists
resource "azurerm_resource_group" "mgmt" {
  name     = "rg-${local.name}-mgmt"
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "dns" {
  name     = "rg-${local.name}-dns"
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "app" {
  name     = "rg-${local.name}-app"
  location = var.location
  # Content is managed by the stack layer; bootstrap only owns the container.
  tags = merge(local.tags, { layer = "stack" })
}
