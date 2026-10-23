# Spoke (workload) VNet, peered with the hub. It is never peered with any
# other spoke: the hub is the only management path into it.

resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-${local.name}-spoke"
  location            = local.location
  resource_group_name = local.rg
  address_space       = [var.spoke_address_space]
  tags                = local.tags
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = local.rg
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [local.spoke_subnets.app]

  # Egress goes through the VM's own public IP; no implicit default outbound.
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = local.rg
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [local.spoke_subnets.private_endpoints]

  default_outbound_access_enabled = false

  # Without this, NSG rules are NOT evaluated for private endpoint traffic.
  private_endpoint_network_policies = "Enabled"
}

# --- NSG: app subnet ---------------------------------------------------------
# Internet: only 443 (and 80, which nginx redirects to HTTPS).
# SSH: only from the hub agents subnet, over the peering.

resource "azurerm_network_security_group" "app" {
  #checkov:skip=CKV_AZURE_160:Port 80 only answers with a redirect to HTTPS (nginx); HSTS is set on 443.

  name                = "nsg-${local.name}-app"
  location            = local.location
  resource_group_name = local.rg
  tags                = local.tags

  security_rule {
    name                       = "allow-https-from-internet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = local.spoke_subnets.app
  }

  security_rule {
    name                       = "allow-http-redirect-from-internet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = local.spoke_subnets.app
  }

  security_rule {
    name                       = "allow-ssh-from-agents"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.bootstrap.agents_subnet_prefix
    destination_address_prefix = local.spoke_subnets.app
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

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

# --- NSG: private endpoints --------------------------------------------------
# Data services are reachable only from the app subnet (runtime) and the
# agents subnet (Terraform writes secrets, Ansible creates the SQL user).

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-${local.name}-spoke-pe"
  location            = local.location
  resource_group_name = local.rg
  tags                = local.tags

  security_rule {
    name                       = "allow-app-to-data"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "1433"]
    source_address_prefix      = local.spoke_subnets.app
    destination_address_prefix = local.spoke_subnets.private_endpoints
  }

  security_rule {
    name                       = "allow-agents-to-data"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "1433"]
    source_address_prefix      = local.bootstrap.agents_subnet_prefix
    destination_address_prefix = local.spoke_subnets.private_endpoints
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

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

# --- Peering (both directions) -----------------------------------------------
# The agent has Network Contributor on the hub VNet only (bootstrap), enough
# to create the hub side of the peering.

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-spoke-to-hub"
  resource_group_name       = local.rg
  virtual_network_name      = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = local.bootstrap.hub_vnet.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-hub-to-${local.name}-spoke"
  resource_group_name       = local.bootstrap.resource_groups.mgmt
  virtual_network_name      = local.bootstrap.hub_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.spoke.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# --- Shared private DNS zones: link the spoke --------------------------------

resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  for_each = local.bootstrap.private_dns_zone_ids

  name                 = "link-${local.name}-spoke"
  private_dns_zone_id  = each.value
  virtual_network_id   = azurerm_virtual_network.spoke.id
  registration_enabled = false
  tags                 = local.tags
}
