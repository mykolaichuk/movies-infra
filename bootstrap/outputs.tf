output "tfstate_storage_account" {
  value = azurerm_storage_account.tfstate.name
}

# Partial backend configuration for every layer. Bootstrap writes it to
# backend.hcl and migrates its own state; the stack uses the same file with a
# different key.
output "backend_hcl" {
  value = <<-EOT
    resource_group_name  = "${azurerm_resource_group.mgmt.name}"
    storage_account_name = "${azurerm_storage_account.tfstate.name}"
    container_name       = "${azurerm_storage_container.tfstate.name}"
    use_azuread_auth     = true
  EOT
}

output "resource_groups" {
  value = {
    mgmt = azurerm_resource_group.mgmt.name
    dns  = azurerm_resource_group.dns.name
    app  = azurerm_resource_group.app.name
  }
}

output "hub_vnet" {
  value = {
    id   = azurerm_virtual_network.hub.id
    name = azurerm_virtual_network.hub.name
  }
}

output "agents_subnet_prefix" {
  description = "The only source allowed to SSH into the app VM (stack NSG)."
  value       = local.hub_subnets.agents
}

output "private_dns_zone_ids" {
  value = { for k, z in azurerm_private_dns_zone.this : k => z.id }
}

output "agent_identity" {
  value = {
    id           = azurerm_user_assigned_identity.agent.id
    client_id    = azurerm_user_assigned_identity.agent.client_id
    principal_id = azurerm_user_assigned_identity.agent.principal_id
  }
}

output "agent_public_ip" {
  description = "Egress IP of the agent (useful for allow-lists, never for inbound)."
  value       = azurerm_public_ip.agent.ip_address
}

output "azdo" {
  value = {
    agent_pool         = azuredevops_agent_pool.this.name
    service_connection = azuredevops_serviceendpoint_azurerm.this.service_endpoint_name
    environments       = { for k, e in azuredevops_environment.this : k => e.name }
  }
}
