# One shared set of privatelink zones for the whole project.
# A VNet can be linked to only ONE zone with a given name, and the agent must
# resolve both the state account (hub) and the workload endpoints (spoke),
# so both VNets link to these same zones. The stack layer adds the spoke link.
#
# DNS is not a security boundary: NSG, RBAC and endpoint placement are.

locals {
  private_dns_zones = {
    blob     = "privatelink.blob.core.windows.net"
    queue    = "privatelink.queue.core.windows.net"
    table    = "privatelink.table.core.windows.net"
    sql      = "privatelink.database.windows.net"
    keyvault = "privatelink.vaultcore.azure.net"
  }
}

resource "azurerm_private_dns_zone" "this" {
  for_each = local.private_dns_zones

  name                = each.value
  resource_group_name = azurerm_resource_group.dns.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each = azurerm_private_dns_zone.this

  name                 = "link-${local.name}-hub"
  private_dns_zone_id  = each.value.id
  virtual_network_id   = azurerm_virtual_network.hub.id
  registration_enabled = false
  tags                 = local.tags
}
