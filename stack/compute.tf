# App VM: nginx + Node.js (web + worker) under systemd, configured by
# Ansible from the agent. Nothing is installed here; the VM starts as a
# plain Ubuntu image.

# User-assigned identity: it exists before the VM, so role assignments,
# the SQL user and the app configuration can all reference it up front.
resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${local.name}-app"
  location            = local.location
  resource_group_name = local.rg
  tags                = local.tags
}

resource "azurerm_public_ip" "app" {
  name                = "pip-${local.name}-app"
  location            = local.location
  resource_group_name = local.rg
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_network_interface" "app" {
  #checkov:skip=CKV_AZURE_119:The app VM is the public entry point (443/80 only, NSG). Production alternative: Application Gateway in front of a private VM.

  name                = "nic-${local.name}-app"
  location            = local.location
  resource_group_name = local.rg
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.app.id
  }
}

# SSH key for Ansible. The private half goes to Key Vault, where only the
# agent can read it, and it also sits in the (private, Entra-only) state.
# Trade-off documented in docs/architecture/current-vs-secure.md; the next
# step would be Entra ID SSH login with the agent's managed identity.
resource "tls_private_key" "ansible" {
  algorithm = "ED25519"
}

resource "azurerm_linux_virtual_machine" "app" {
  #checkov:skip=CKV_AZURE_50:The Azure Monitor Agent extension is required for logs and metrics.

  name                = "vm-${local.name}-app"
  computer_name       = "${local.name}-app"
  location            = local.location
  resource_group_name = local.rg
  size                = var.app_vm_size

  network_interface_ids = [azurerm_network_interface.app.id]

  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ansible.public_key_openssh
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server-arm64"
    version   = "latest"
  }

  os_disk {
    name                 = "osdisk-${local.name}-app"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64 # room for the nginx video cache
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  boot_diagnostics {}

  tags = merge(local.tags, { role = "app" })
}

# Azure Monitor Agent, authenticating with the VM's user-assigned identity.
resource "azurerm_virtual_machine_extension" "ama" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.app.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true

  settings = jsonencode({
    authentication = {
      managedIdentity = {
        "identifier-name"  = "mi_res_id"
        "identifier-value" = azurerm_user_assigned_identity.app.id
      }
    }
  })

  tags = local.tags
}
