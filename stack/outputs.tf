# Non-sensitive outputs are exported by the pipeline as the 'stack-outputs'
# artifact and consumed by movies-configuration (Ansible) and movies-app.
# Nothing secret is ever an output: secrets live only in Key Vault.

output "dns_name_servers" {
  description = "Add these as NS records for domain_name in its parent zone (e.g. Cloudflare)."
  value       = azurerm_dns_zone.public.name_servers
}

output "domain_name" {
  value = var.domain_name
}

output "dns_zone" {
  description = "Public zone for certbot DNS-01 (movies-configuration maps the zone to its resource group)."
  value = {
    name = azurerm_dns_zone.public.name
    id   = azurerm_dns_zone.public.id
  }
}

output "app_vm" {
  value = {
    name         = azurerm_linux_virtual_machine.app.name
    private_ip   = azurerm_network_interface.app.private_ip_address
    public_ip    = azurerm_public_ip.app.ip_address
    admin_user   = var.admin_username
    ssh_key_name = "ansible-ssh-private-key"
  }
}

output "app_identity" {
  description = "Managed identity of the app VM (DefaultAzureCredential uses client_id; SQL user uses object_id)."
  value = {
    name      = azurerm_user_assigned_identity.app.name
    client_id = azurerm_user_assigned_identity.app.client_id
    object_id = azurerm_user_assigned_identity.app.principal_id
  }
}

output "sql" {
  value = {
    server_fqdn = azurerm_mssql_server.this.fully_qualified_domain_name
    database    = azurerm_mssql_database.catalog.name
  }
}

output "storage" {
  value = {
    account    = azurerm_storage_account.app.name
    blob_url   = azurerm_storage_account.app.primary_blob_endpoint
    queue_url  = azurerm_storage_account.app.primary_queue_endpoint
    table_url  = azurerm_storage_account.app.primary_table_endpoint
    containers = keys(azurerm_storage_container.media)
    queue      = azurerm_storage_queue.jobs.name
    table      = "counters" # created by the app at start-up (see data.tf)
  }
}

output "key_vault" {
  value = {
    name    = azurerm_key_vault.this.name
    uri     = azurerm_key_vault.this.vault_uri
    secrets = concat(keys(azurerm_key_vault_secret.this), ["tmdb-read-token"]) # the last one: pipelines/set-secret.yml
  }
}

output "entra_app" {
  value = {
    client_id       = azuread_application.movies.client_id
    tenant_id       = local.tenant_id
    redirect_uri    = "https://${var.domain_name}/auth/callback"
    admin_object_id = var.admin_object_id
    # Everyone allowed into /admin: the owner first, then app_admin_object_ids.
    admin_object_ids = distinct(concat([lower(var.admin_object_id)], [for id in var.app_admin_object_ids : lower(id)]))
  }
}

output "monitoring" {
  value = {
    # Not a secret here: local auth is disabled, ingestion also needs an Entra token.
    app_insights_connection_string = nonsensitive(azurerm_application_insights.this.connection_string)
    log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.workspace_id
    grafana_url                    = azurerm_dashboard_grafana.this.endpoint
  }
}
