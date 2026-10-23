# Every role assignment of the stack in one place. The agent can grant only
# the roles allow-listed by the ABAC condition in bootstrap/identity.tf;
# anything else fails at apply time by design.

locals {
  app_identity = azurerm_user_assigned_identity.app.principal_id

  role_assignments = {
    # App VM identity: exactly the data it touches, nothing more.
    app_blob = {
      scope     = azurerm_storage_account.app.id
      role      = "Storage Blob Data Contributor"
      principal = local.app_identity
      type      = "ServicePrincipal"
      why       = "App: read videos/posters, write thumbnails"
    }
    app_queue = {
      scope     = azurerm_storage_account.app.id
      role      = "Storage Queue Data Contributor"
      principal = local.app_identity
      type      = "ServicePrincipal"
      why       = "App: enqueue and process image jobs"
    }
    app_table = {
      scope     = azurerm_storage_account.app.id
      role      = "Storage Table Data Contributor"
      principal = local.app_identity
      type      = "ServicePrincipal"
      why       = "App: view and like counters"
    }
    app_kv = {
      scope     = azurerm_key_vault.this.id
      role      = "Key Vault Secrets User"
      principal = local.app_identity
      type      = "ServicePrincipal"
      why       = "App: read runtime secrets"
    }
    app_dns = {
      scope     = azurerm_dns_zone.public.id
      role      = "DNS Zone Contributor"
      principal = local.app_identity
      type      = "ServicePrincipal"
      why       = "certbot DNS-01 on this zone only"
    }
    app_ai = {
      scope     = azurerm_application_insights.this.id
      role      = "Monitoring Metrics Publisher"
      principal = local.app_identity
      type      = "ServicePrincipal"
      why       = "App: send telemetry with Entra auth"
    }

    # Grafana reads monitoring data of the workload RG.
    grafana_monitoring = {
      scope     = data.azurerm_resource_group.app.id
      role      = "Monitoring Reader"
      principal = azurerm_dashboard_grafana.this.identity[0].principal_id
      type      = "ServicePrincipal"
      why       = "Grafana: Azure Monitor data source"
    }
    grafana_logs = {
      scope     = azurerm_log_analytics_workspace.this.id
      role      = "Log Analytics Reader"
      principal = azurerm_dashboard_grafana.this.identity[0].principal_id
      type      = "ServicePrincipal"
      why       = "Grafana: Log Analytics queries"
    }

    # The human admin administers Grafana.
    admin_grafana = {
      scope     = azurerm_dashboard_grafana.this.id
      role      = "Grafana Admin"
      principal = var.admin_object_id
      type      = "User"
      why       = "Admin: Grafana dashboards"
    }
  }
}

resource "azurerm_role_assignment" "this" {
  for_each = local.role_assignments

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = each.value.principal
  principal_type       = each.value.type
  description          = each.value.why
}
