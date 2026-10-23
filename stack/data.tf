# Data services: Azure SQL (catalog) and Storage (media, jobs, counters).
# None of them has a public endpoint or a password/key: managed identities
# over private endpoints only.

# --- Azure SQL ---------------------------------------------------------------

resource "azurerm_mssql_server" "this" {
  #checkov:skip=CKV_AZURE_23:Auditing to Log Analytics would eat the free 5 GB ingestion; documented demo trade-off.
  #checkov:skip=CKV_AZURE_24:Auditing retention: see CKV_AZURE_23.
  #checkov:skip=CKV2_AZURE_45:Microsoft Defender for SQL is a paid plan; out of scope for the demo.
  #checkov:skip=CKV2_AZURE_2:Vulnerability assessment requires Defender for SQL (paid).
  #checkov:skip=CKV2_AZURE_27:Entra-only authentication is configured below (azuread_authentication_only = true).

  name                          = "sql-${local.name}-${random_string.suffix.result}"
  resource_group_name           = local.rg
  location                      = local.location
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false

  # No SQL logins at all. The agent's identity is the Entra admin, so Ansible
  # (running on the agent) can create the database user for the app identity.
  azuread_administrator {
    login_username              = "id-${local.name}-agent"
    object_id                   = local.agent_principal_id
    tenant_id                   = local.tenant_id
    azuread_authentication_only = true
  }

  tags = local.tags
}

resource "azurerm_mssql_database" "catalog" {
  #checkov:skip=CKV_AZURE_224:Ledger is not needed for a film catalog.
  #checkov:skip=CKV_AZURE_229:Zone redundancy is a documented SPOF (spof.md).

  name      = "sqldb-${local.name}"
  server_id = azurerm_mssql_server.this.id

  # Basic (5 DTU, 2 GB): a fixed ~5 USD/month, enough for a small catalog.
  # Serverless (GP_S_Gen5_1) was dropped: internet bots requesting the home
  # page woke it every hour, so it billed ~6 USD/day at its 0.5 vCore minimum.
  sku_name             = "Basic"
  max_size_gb          = 2
  storage_account_type = "Local"
  zone_redundant       = false

  tags = local.tags
}

# --- Storage -----------------------------------------------------------------

resource "azurerm_storage_account" "app" {
  #checkov:skip=CKV_AZURE_206:Demo cost decision: LRS is a documented SPOF (spof.md).
  #checkov:skip=CKV2_AZURE_1:Platform-managed keys are sufficient for openly licensed media.
  #checkov:skip=CKV_AZURE_33:Queue logging would consume the free Log Analytics allowance.
  #checkov:skip=CKV_AZURE_59:False positive: azurerm 5.x renamed the attribute to public_network_access, which is "Disabled" below.

  name                = "st${local.name}app${random_string.suffix.result}"
  resource_group_name = local.rg
  location            = local.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  shared_access_key_enabled        = false # no keys, no SAS: managed identity only
  default_to_oauth_authentication  = true
  allow_nested_items_to_be_public  = false
  public_network_access            = "Disabled"
  cross_tenant_replication_enabled = false

  blob_properties {
    versioning_enabled = false # videos are immutable; versioning would double storage

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  tags = local.tags
}

# Containers and the queue are created through ARM (storage_account_id),
# so Terraform does not need the data plane for them.
#
# The 'counters' table is NOT created here: with shared keys disabled, the
# ARM table API answers 403 (the Storage resource provider serves tables
# through the data plane). The app creates it at start-up with its managed
# identity (Storage Table Data Contributor), createTable-if-not-exists.
resource "azurerm_storage_container" "media" {
  #checkov:skip=CKV2_AZURE_21:Blob read logging would consume the free Log Analytics allowance.
  for_each = toset(["videos", "posters", "thumbnails"])

  name                  = each.value
  storage_account_id    = azurerm_storage_account.app.id
  container_access_type = "private"
}

resource "azurerm_storage_queue" "jobs" {
  name               = "image-jobs"
  storage_account_id = azurerm_storage_account.app.id
}

# --- Private endpoints -------------------------------------------------------

locals {
  private_endpoints = {
    blob  = { resource_id = azurerm_storage_account.app.id, subresource = "blob", zone = "blob" }
    queue = { resource_id = azurerm_storage_account.app.id, subresource = "queue", zone = "queue" }
    table = { resource_id = azurerm_storage_account.app.id, subresource = "table", zone = "table" }
    sql   = { resource_id = azurerm_mssql_server.this.id, subresource = "sqlServer", zone = "sql" }
    vault = { resource_id = azurerm_key_vault.this.id, subresource = "vault", zone = "keyvault" }
  }
}

resource "azurerm_private_endpoint" "this" {
  for_each = local.private_endpoints

  name                = "pe-${local.name}-${each.key}"
  location            = local.location
  resource_group_name = local.rg
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = local.tags

  # Without this Azure names the NIC "<pe-name>.nic.<guid>".
  custom_network_interface_name = "nic-pe-${local.name}-${each.key}"

  private_service_connection {
    name                           = "psc-${each.key}"
    private_connection_resource_id = each.value.resource_id
    subresource_names              = [each.value.subresource]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.bootstrap.private_dns_zone_ids[each.value.zone]]
  }

  # DNS for the endpoint must resolve from the agent and the app VM.
  depends_on = [azurerm_private_dns_zone_virtual_network_link.spoke]
}
