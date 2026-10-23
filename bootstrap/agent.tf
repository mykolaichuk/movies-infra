# Self-hosted Azure DevOps agent in the hub.
# Inbound: nothing (NSG deny-all). Outbound: HTTPS to dev.azure.com, package
# repositories and Azure APIs through its own public IP.

resource "azurerm_public_ip" "agent" {
  name                = "pip-${local.name}-agent"
  location            = azurerm_resource_group.mgmt.location
  resource_group_name = azurerm_resource_group.mgmt.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_network_interface" "agent" {
  #checkov:skip=CKV_AZURE_119:Egress-only public IP (NSG denies all inbound). Production alternative: NAT Gateway.

  name                = "nic-${local.name}-agent"
  location            = azurerm_resource_group.mgmt.location
  resource_group_name = azurerm_resource_group.mgmt.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.agents.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.agent.id
  }
}

resource "azurerm_linux_virtual_machine" "agent" {
  #checkov:skip=CKV_AZURE_50:VM extensions stay enabled for the run-command break-glass path.

  name                = "vm-${local.name}-agent"
  computer_name       = "${local.name}-agent"
  location            = azurerm_resource_group.mgmt.location
  resource_group_name = azurerm_resource_group.mgmt.name
  size                = var.agent_vm_size

  network_interface_ids = [azurerm_network_interface.agent.id]

  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server-arm64"
    version   = "latest"
  }

  os_disk {
    name                 = "osdisk-${local.name}-agent"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.agent.id]
  }

  # Managed boot diagnostics: serial console is the break-glass path,
  # since there is no inbound SSH.
  boot_diagnostics {}

  custom_data = base64encode(templatefile("${path.module}/templates/agent-cloud-init.yaml.tftpl", {
    azdo_org_url    = var.azdo_org_url
    azdo_pool       = azuredevops_agent_pool.this.name
    azdo_pat        = var.azdo_pat
    agent_version   = var.agent_version
    agent_sha256    = var.agent_sha256
    agent_name      = "${local.name}-agent-01"
    uami_client_id  = azurerm_user_assigned_identity.agent.client_id
    subscription_id = var.subscription_id
    tenant_id       = data.azurerm_client_config.current.tenant_id
  }))

  tags = merge(local.tags, { role = "build-agent" })

  lifecycle {
    # custom_data carries the one-time PAT. Rotating or revoking the PAT must
    # not rebuild a registered agent.
    ignore_changes = [custom_data]
  }

  # The pool must exist before the agent tries to register into it.
  depends_on = [azuredevops_agent_queue.this]
}
