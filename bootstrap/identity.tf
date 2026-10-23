# One user-assigned managed identity for the build agent.
# It is attached to the agent VM (Terraform/Ansible/az use it directly via
# IMDS) and backs the Azure DevOps service connection through workload
# identity federation (see azdo.tf). No client secrets anywhere.

resource "azurerm_user_assigned_identity" "agent" {
  name                = "id-${local.name}-agent"
  location            = azurerm_resource_group.mgmt.location
  resource_group_name = azurerm_resource_group.mgmt.name
  tags                = local.tags
}

# --- Azure RBAC: least privilege, scoped per resource group -------------------

# Build everything in the workload RG.
resource "azurerm_role_assignment" "agent_app_contributor" {
  scope                = azurerm_resource_group.app.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
  principal_type       = "ServicePrincipal"
  description          = "Agent: create and manage workload resources"
}

# The stack grants data-plane roles (VM identity -> Storage, Key Vault, ...).
# Contributor cannot write role assignments, and Owner/User Access
# Administrator would let the agent grant ANY role. Instead: RBAC
# Administrator constrained by an ABAC condition to an explicit allow-list.
locals {
  delegable_roles = [
    "DNS Zone Contributor",
    "Grafana Admin",
    "Key Vault Secrets Officer",
    "Key Vault Secrets User",
    "Log Analytics Reader",
    "Monitoring Metrics Publisher",
    "Monitoring Reader",
    "Storage Blob Data Contributor",
    "Storage Blob Data Reader",
    "Storage Queue Data Contributor",
    "Storage Queue Data Message Processor",
    "Storage Table Data Contributor",
  ]
}

data "azurerm_role_definition" "delegable" {
  for_each = toset(local.delegable_roles)
  name     = each.value
  scope    = data.azurerm_subscription.current.id
}

locals {
  delegable_role_guids = join(", ", sort([
    for r in data.azurerm_role_definition.delegable : r.role_definition_id
  ]))

  rbac_admin_condition = <<-EOT
    (
      (
        !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
      )
      OR
      (
        @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.delegable_role_guids}}
      )
    )
    AND
    (
      (
        !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
      )
      OR
      (
        @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.delegable_role_guids}}
      )
    )
  EOT
}

resource "azurerm_role_assignment" "agent_app_rbac_admin" {
  scope                = azurerm_resource_group.app.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
  principal_type       = "ServicePrincipal"
  condition            = local.rbac_admin_condition
  condition_version    = "2.0"
  description          = "Agent: assign only allow-listed data-plane roles inside the workload RG"
}

# Link the spoke VNet to the shared zones and register spoke endpoints.
resource "azurerm_role_assignment" "agent_dns" {
  scope                = azurerm_resource_group.dns.id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
  principal_type       = "ServicePrincipal"
  description          = "Agent: link spoke VNet and add private endpoint records"
}

# Peering needs rights on BOTH VNets; the hub side is scoped to the VNet only.
resource "azurerm_role_assignment" "agent_hub_vnet" {
  scope                = azurerm_virtual_network.hub.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
  principal_type       = "ServicePrincipal"
  description          = "Agent: create hub-to-spoke peering"
}

# Read and write Terraform state through the private endpoint.
resource "azurerm_role_assignment" "agent_tfstate" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
  principal_type       = "ServicePrincipal"
  description          = "Agent: Terraform remote state"
}

# --- Microsoft Graph: manage only the app registrations it creates -----------
# Used by the stack to create the Entra ID app for admin sign-in.
# Application.ReadWrite.OwnedBy cannot touch any app it does not own.

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

resource "azuread_app_role_assignment" "agent_graph_owned_apps" {
  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids["Application.ReadWrite.OwnedBy"]
  principal_object_id = azurerm_user_assigned_identity.agent.principal_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}
