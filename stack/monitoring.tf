# Observability on a budget:
#   - one Log Analytics workspace with a daily cap (free 5 GB/month allowance),
#   - workspace-based Application Insights with Entra-only ingestion,
#   - Azure Monitor Agent collecting VM performance counters and syslog,
#     including nginx access/error logs (nginx logs to syslog facility local7,
#     configured by Ansible, so no custom tables are needed),
#   - Azure Managed Grafana on top.

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.name}"
  location            = local.location
  resource_group_name = local.rg
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${local.name}"
  location            = local.location
  resource_group_name = local.rg
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "Node.JS"
  sampling_percentage = 50

  # Ingestion only with an Entra token (the app's managed identity): the
  # connection string alone is no longer enough to send telemetry.
  local_authentication_enabled = false

  tags = local.tags
}

resource "azurerm_monitor_data_collection_rule" "vm" {
  name                = "dcr-${local.name}-vm"
  location            = local.location
  resource_group_name = local.rg
  kind                = "Linux"
  description         = "App VM: performance counters, auth/system syslog, nginx (local7)"
  tags                = local.tags

  destinations {
    log_analytics {
      name                  = "law"
      workspace_resource_id = azurerm_log_analytics_workspace.this.id
    }
  }

  data_sources {
    performance_counter {
      name                          = "perf"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "Processor(*)\\% Processor Time",
        "Memory(*)\\% Used Memory",
        "Logical Disk(*)\\% Used Space",
        "Network(*)\\Total Bytes Received",
        "Network(*)\\Total Bytes Transmitted",
      ]
    }

    # Security-relevant and service logs at warning level.
    syslog {
      name           = "system"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["auth", "authpriv", "daemon", "kern"]
      log_levels     = ["Warning", "Error", "Critical", "Alert", "Emergency"]
    }

    # nginx access and error logs (Ansible: access_log syslog:...,facility=local7).
    syslog {
      name           = "nginx"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["local7"]
      log_levels     = ["Info", "Notice", "Warning", "Error", "Critical", "Alert", "Emergency"]
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Syslog"]
    destinations = ["law"]
  }
}

resource "azurerm_monitor_data_collection_rule_association" "vm" {
  name                    = "dcra-${local.name}-vm"
  target_resource_id      = azurerm_linux_virtual_machine.app.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.vm.id

  depends_on = [azurerm_virtual_machine_extension.ama]
}

resource "azurerm_dashboard_grafana" "this" {
  name                              = "amg-${local.name}-${random_string.suffix.result}"
  location                          = var.grafana_location
  resource_group_name               = local.rg
  sku                               = "Standard"
  grafana_major_version             = "12"
  api_key_enabled                   = false
  deterministic_outbound_ip_enabled = false
  public_network_access_enabled     = true # UI behind Entra ID sign-in

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

# --- Smart detection, owned by Terraform -------------------------------------
# Creating Application Insights makes Azure add, outside Terraform, an action
# group "Application Insights Smart Detection" and an alert rule
# "Failure Anomalies - <appi>". imports.tf adopts those two; the names below
# then force Terraform to replace them with correctly named ones.

resource "azurerm_monitor_action_group" "smart_detection" {
  name                = "ag-${local.name}-smart-detection"
  resource_group_name = local.rg
  short_name          = "smartdetect" # max 12 characters, shown in notifications
  tags                = local.tags

  # Same receivers Azure would generate: e-mail whoever holds these roles.
  arm_role_receiver {
    name                    = "Monitoring Contributor"
    role_id                 = "749f88d5-cbae-40b8-bcfc-e573ddc772fa"
    use_common_alert_schema = true
  }

  arm_role_receiver {
    name                    = "Monitoring Reader"
    role_id                 = "43d0d8ad-25c7-4714-9337-8ba259a9fe05"
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_smart_detector_alert_rule" "failure_anomalies" {
  name                = "sdar-${local.name}-failure-anomalies"
  resource_group_name = local.rg
  description         = "Failure Anomalies: abnormal rise in failed requests of ${azurerm_application_insights.this.name}"
  detector_type       = "FailureAnomaliesDetector"
  scope_resource_ids  = [azurerm_application_insights.this.id]
  severity            = "Sev3"
  frequency           = "PT1M"
  tags                = local.tags

  action_group {
    ids = [azurerm_monitor_action_group.smart_detection.id]
  }
}

