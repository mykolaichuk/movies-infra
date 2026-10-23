# --- Link to the bootstrap layer ---------------------------------------------

variable "tfstate_storage_account" {
  description = "Storage account that holds every state file (from ../backend.hcl; the pipeline passes it)."
  type        = string
}

variable "tfstate_resource_group" {
  description = "Resource group of the state storage account."
  type        = string
  default     = "rg-movies-mgmt"
}

# --- General -----------------------------------------------------------------

variable "prefix" {
  description = "Short name used in every resource name (must match bootstrap)."
  type        = string
  default     = "movies"
}

variable "tags" {
  description = "Extra tags merged into the default tag set."
  type        = map(string)
  default     = {}
}

# --- Network -----------------------------------------------------------------

variable "spoke_address_space" {
  description = "Address space of the spoke (workload) VNet."
  type        = string
  default     = "10.20.0.0/16"
}

# --- DNS / TLS ---------------------------------------------------------------

variable "domain_name" {
  description = "Public host name of the app, e.g. movies.example.com. Azure DNS hosts it as its own zone; the parent zone delegates it with NS records."
  type        = string
}

# --- App VM ------------------------------------------------------------------

variable "app_vm_size" {
  description = "Arm64 burstable size for the app VM."
  type        = string
  default     = "Standard_B2pls_v2"
}

variable "admin_username" {
  description = "Local admin account on the app VM (SSH key only, reachable only from the agents subnet)."
  type        = string
  default     = "azureuser"
}

# --- Admin and secrets -------------------------------------------------------

variable "admin_object_id" {
  description = "Entra ID object ID of the human admin: signs in to the app and administers Grafana (az ad signed-in-user show --query id -o tsv)."
  type        = string
}

variable "app_admin_object_ids" {
  description = "Entra ID object IDs of further users allowed into the app's admin area (users of this tenant). admin_object_id is always an admin; this list grants no Azure roles."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.app_admin_object_ids : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))])
    error_message = "Every app_admin_object_ids entry must be an Entra object ID (GUID)."
  }
}

variable "secrets_expire_on" {
  description = "Expiry of every Key Vault secret and of the Entra client secret (RFC 3339)."
  type        = string
  default     = "2027-06-30T00:00:00Z"
}

# --- Monitoring --------------------------------------------------------------

variable "log_daily_quota_gb" {
  description = "Log Analytics daily cap; ~0.15 GB/day keeps the demo inside the free 5 GB/month."
  type        = number
  default     = 0.15
}

variable "grafana_location" {
  description = "Region for Azure Managed Grafana (it may live outside the workload region)."
  type        = string
  default     = "swedencentral"
}
