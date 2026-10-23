# Azure DevOps side of the bootstrap, also as code:
#   agent pool + project queue, the Azure service connection (workload
#   identity federation, no secret) and protected environments with approvals.

data "azuredevops_project" "this" {
  name = var.azdo_project_name
}

# --- Self-hosted agent pool --------------------------------------------------

resource "azuredevops_agent_pool" "this" {
  name           = var.azdo_agent_pool_name
  auto_provision = false
  auto_update    = true # the agent updates itself; the VM image does not need rebuilding
}

resource "azuredevops_agent_queue" "this" {
  project_id    = data.azuredevops_project.this.id
  agent_pool_id = azuredevops_agent_pool.this.id
}

# No pipeline_id: the queue is authorised for every pipeline in the project.
resource "azuredevops_pipeline_authorization" "queue" {
  project_id  = data.azuredevops_project.this.id
  resource_id = azuredevops_agent_queue.this.id
  type        = "queue"
}

# --- Service connection: workload identity federation with the agent UAMI ----
# Azure DevOps issues a short-lived OIDC token per job; Entra ID trusts it via
# the federated credential below. Nothing to rotate, nothing to leak.

resource "azuredevops_serviceendpoint_azurerm" "this" {
  project_id                             = data.azuredevops_project.this.id
  service_endpoint_name                  = var.azdo_service_connection_name
  description                            = "Movies demo: managed by movies-infra/bootstrap"
  service_endpoint_authentication_scheme = "WorkloadIdentityFederation"

  azurerm_spn_tenantid      = data.azurerm_client_config.current.tenant_id
  azurerm_subscription_id   = data.azurerm_subscription.current.subscription_id
  azurerm_subscription_name = data.azurerm_subscription.current.display_name

  credentials {
    serviceprincipalid = azurerm_user_assigned_identity.agent.client_id
  }
}

resource "azurerm_federated_identity_credential" "azdo" {
  name                      = "azdo-${var.azdo_service_connection_name}"
  user_assigned_identity_id = azurerm_user_assigned_identity.agent.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azuredevops_serviceendpoint_azurerm.this.workload_identity_federation_issuer
  subject                   = azuredevops_serviceendpoint_azurerm.this.workload_identity_federation_subject
}

# Pipelines must be authorised one by one (stack layer), not "all pipelines".

# --- Environments: approvals gate every change to infrastructure and config --

data "azuredevops_identity_user" "approver" {
  name          = var.approver_email
  search_filter = "MailAddress"
}

locals {
  environments = {
    infra  = { name = "movies-infra", approval = true }
    config = { name = "movies-config", approval = true }
    app    = { name = "movies-app", approval = false } # app deploys flow on green builds
  }
}

resource "azuredevops_environment" "this" {
  for_each = local.environments

  project_id  = data.azuredevops_project.this.id
  name        = each.value.name
  description = "Movies demo: ${each.key} deployments"
}

resource "azuredevops_check_approval" "this" {
  for_each = { for k, v in local.environments : k => v if v.approval }

  project_id           = data.azuredevops_project.this.id
  target_resource_id   = azuredevops_environment.this[each.key].id
  target_resource_type = "environment"

  approvers             = [data.azuredevops_identity_user.approver.id]
  requester_can_approve = true # single-maintainer demo; in a team, set false (four-eyes)
  instructions          = "Review the plan / --check --diff output in the previous stage before approving."
  timeout               = 1440
}
