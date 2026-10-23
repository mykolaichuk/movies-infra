# Hub (management) VNet: build agent + private endpoint for Terraform state.
# Peering to the spoke is created by the stack layer.

# One Network Watcher per region per subscription. Owning it keeps naming and
# tags consistent and stops Azure from auto-creating NetworkWatcherRG for the
# first VNet (here or in the stack layer).
resource "azurerm_network_watcher" "this" {
  name                = "nw-${local.name}-${var.location}"
  location            = azurerm_resource_group.mgmt.location
  resource_group_name = azurerm_resource_group.mgmt.name
  tags                = local.tags
}

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-${local.name}-hub"
  location            = azurerm_resource_group.mgmt.location
  resource_group_name = azurerm_resource_group.mgmt.name
  address_space       = [var.hub_address_space]
  tags                = local.tags

  # The watcher must exist first, or Azure auto-creates its own for this region.
  depends_on = [azurerm_network_watcher.this]
}

resource "azurerm_subnet" "agents" {
  name                 = "snet-agents"
  resource_group_name  = azurerm_resource_group.mgmt.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.hub_subnets.agents]

  # New VNets get no implicit internet egress; the agent's public IP
  # provides explicit outbound connectivity instead.
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "hub_private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.mgmt.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.hub_subnets.private_endpoints]

  default_outbound_access_enabled = false

  # Without this, NSG rules are NOT evaluated for private endpoint traffic.
  private_endpoint_network_policies = "Enabled"
}

# --- NSG: the agent accepts NO inbound traffic at all ------------------------
# It only opens outbound HTTPS to dev.azure.com (long polling) and pulls jobs.

resource "azurerm_network_security_group" "agents" {
  name                = "nsg-${local.name}-agents"
  location            = azurerm_resource_group.mgmt.location
  resource_group_name = azurerm_resource_group.mgmt.name
  tags                = local.tags

  # Explicit rule instead of relying on defaults: it overrides the default
  # AllowVnetInBound and makes the intent visible in the portal.
  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "agents" {
  subnet_id                 = azurerm_subnet.agents.id
  network_security_group_id = azurerm_network_security_group.agents.id
}

resource "azurerm_network_security_group" "hub_private_endpoints" {
  name                = "nsg-${local.name}-hub-pe"
  location            = azurerm_resource_group.mgmt.location
  resource_group_name = azurerm_resource_group.mgmt.name
  tags                = local.tags

  # Only the agents subnet may reach the Terraform state endpoint.
  security_rule {
    name                       = "allow-agents-https"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = local.hub_subnets.agents
    destination_address_prefix = local.hub_subnets.private_endpoints
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "hub_private_endpoints" {
  subnet_id                 = azurerm_subnet.hub_private_endpoints.id
  network_security_group_id = azurerm_network_security_group.hub_private_endpoints.id
}
