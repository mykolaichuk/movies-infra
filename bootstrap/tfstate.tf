# Remote state for every Terraform layer of the project.
#
# Lifecycle of public network access (chicken-and-egg):
#   1. First apply from Cloud Shell: public access ON, but shared keys OFF,
#      so only Entra ID identities with a data role can read or write state.
#   2. Local state is migrated into this account (terraform init -migrate-state).
#   3. Public access is turned OFF with az CLI (see README). Terraform ignores
#      that attribute, because the apply that disables it could no longer
#      write its own state afterwards.
# From then on state is reachable only through the private endpoint in the hub.

resource "azurerm_storage_account" "tfstate" {
  #checkov:skip=CKV_AZURE_59:Public access is disabled with az CLI right after state migration (see README, step 4).
  #checkov:skip=CKV_AZURE_206:Demo cost decision: LRS is a documented SPOF (docs/architecture/spof.md).
  #checkov:skip=CKV2_AZURE_1:Platform-managed keys are sufficient for the demo; CMK adds a Key Vault dependency to bootstrap.
  #checkov:skip=CKV_AZURE_33:Queue service is not used in the state account.

  name                = "st${local.name}tfstate${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.mgmt.name
  location            = azurerm_resource_group.mgmt.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS" # demo: cost over resilience (documented SPOF)

  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  shared_access_key_enabled        = false # no account keys, no SAS: Entra ID only
  default_to_oauth_authentication  = true
  allow_nested_items_to_be_public  = false
  public_network_access            = "Enabled"
  cross_tenant_replication_enabled = false

  blob_properties {
    versioning_enabled = true # every state write is a recoverable version

    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [public_network_access]
  }
}

# Created through the ARM control plane (storage_account_id), so it works even
# when the data plane is unreachable from where Terraform runs.
resource "azurerm_storage_container" "tfstate" {
  #checkov:skip=CKV2_AZURE_21:Blob versioning keeps every state write; read logging would need a Log Analytics workspace before the stack exists.

  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

resource "azurerm_private_endpoint" "tfstate_blob" {
  name                = "pe-${azurerm_storage_account.tfstate.name}-blob"
  location            = azurerm_resource_group.mgmt.location
  resource_group_name = azurerm_resource_group.mgmt.name
  subnet_id           = azurerm_subnet.hub_private_endpoints.id
  tags                = local.tags

  # Without this Azure names the NIC "<pe-name>.nic.<guid>".
  custom_network_interface_name = "nic-pe-${azurerm_storage_account.tfstate.name}-blob"

  private_service_connection {
    name                           = "psc-tfstate-blob"
    private_connection_resource_id = azurerm_storage_account.tfstate.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.this["blob"].id]
  }
}

# The human running bootstrap needs a data-plane role to migrate state.
# Owner/Contributor alone cannot read blobs once shared keys are disabled.
resource "azurerm_role_assignment" "tfstate_bootstrap_operator" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  description          = "Bootstrap operator: migrate and maintain Terraform state"
}
