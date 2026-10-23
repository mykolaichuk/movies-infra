variable "subscription_id" {
  description = "Azure subscription that hosts the whole demo."
  type        = string
}

variable "location" {
  description = "Azure region. Must offer the Arm64 B-series (Bpsv2) sizes."
  type        = string
  default     = "swedencentral"
}

variable "prefix" {
  description = "Short name used in every resource name."
  type        = string
  default     = "movies"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,9}$", var.prefix))
    error_message = "Use 3-10 lowercase letters/digits, starting with a letter (storage account naming rules)."
  }
}

variable "tags" {
  description = "Extra tags merged into the default tag set."
  type        = map(string)
  default     = {}
}

# --- Network -----------------------------------------------------------------

variable "hub_address_space" {
  description = "Address space of the hub (management) VNet."
  type        = string
  default     = "10.10.0.0/16"
}

# --- Build agent VM ----------------------------------------------------------

variable "agent_vm_size" {
  description = "Arm64 burstable size for the build agent."
  type        = string
  default     = "Standard_B2pls_v2"
}

variable "admin_username" {
  description = "Local admin account on the agent VM (SSH key only)."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for the admin account. There is no inbound SSH rule; the key is only for serial console / run-command break-glass."
  type        = string
}

variable "agent_version" {
  description = "Azure Pipelines agent version (https://github.com/microsoft/azure-pipelines-agent/releases)."
  type        = string
  default     = "5.277.0"
}

variable "agent_sha256" {
  description = "SHA-256 of vsts-agent-linux-arm64-<version>.tar.gz from the release page. The download is verified before it is unpacked."
  type        = string
  default     = "0d09e52e4971a88c8c7c1bc23db2b2b462580ea563901ff6adc913d74c331279"
}

# --- Azure DevOps ------------------------------------------------------------

variable "azdo_org_url" {
  description = "Azure DevOps organisation URL, e.g. https://dev.azure.com/<organisation>."
  type        = string
}

variable "azdo_project_name" {
  description = "Azure DevOps project that holds the three repositories."
  type        = string
}

variable "azdo_pat" {
  description = "Short-lived PAT. Scopes: Agent Pools (Read & manage), Service Connections (Read, query & manage), Environment (Read & manage), Pipeline Resources (Use & manage), Build (Read), Project and Team (Read), Identity (Read)."
  type        = string
  sensitive   = true
}

variable "azdo_agent_pool_name" {
  description = "Self-hosted agent pool for every pipeline of the demo."
  type        = string
  default     = "movies-pool"
}

variable "azdo_service_connection_name" {
  description = "Azure Resource Manager service connection (workload identity federation)."
  type        = string
  default     = "sc-movies-azure"
}

variable "approver_email" {
  description = "Azure DevOps user who approves deployments to the protected environments."
  type        = string
}
