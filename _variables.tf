variable "name" {
  description = "Resource name prefix used for all resources in this module."
  type        = string
}

variable "resource_group" {
  description = "Create or use an existing resource group."
  type = object({
    create   = bool
    name     = string
    location = optional(string)
  })
}

variable "tags" {
  description = "Extra tags merged with default tags."
  type        = map(string)
  default     = {}
}

variable "diagnostics" {
  description = "Optional Azure Monitor diagnostic settings."
  type = object({
    enabled                        = optional(bool, false)
    log_analytics_workspace_id     = optional(string)
    storage_account_id             = optional(string)
    eventhub_authorization_rule_id = optional(string)
  })
  default = {}
}

variable "key_vault" {
  description = "Azure Key Vault configuration."
  type = object({
    name        = optional(string)

    sku_name = optional(string, "standard") # standard | premium

    tenant_id = optional(string)

    purge_protection_enabled   = optional(bool, true)
    soft_delete_retention_days = optional(number, 7)

    public_network_access_enabled = optional(bool, false)

    # Optional: network ACLs (when public access enabled or for trusted services)
    network_acls = optional(object({
      bypass                     = optional(string, "AzureServices")
      default_action             = optional(string, "Deny")
      ip_rules                   = optional(list(string), [])
      virtual_network_subnet_ids = optional(list(string), [])
    }))
  })
}

variable "access" {
  description = "Key Vault access model. 'rbac' uses Azure RBAC (default); 'vault_access_policy' uses legacy Vault Access Policies. The caller identity is always added automatically."
  type = object({
    model                 = optional(string, "rbac") # rbac | vault_access_policy
    additional_object_ids = optional(list(string), [])
  })
  default = {}
}

variable "private" {
  type = object({
    enabled = bool

    endpoints = optional(map(bool), {
      vault = true
    })

    pe_subnet_id = optional(string)
    vnet_id      = optional(string)

    dns = optional(object({
      create_zone      = optional(bool, true)
      create_vnet_link = optional(bool, true)

      resource_group = optional(object({
        create   = bool
        name     = string
        location = optional(string)
      }))

      # Legacy compatibility (same pattern as storage module)
      resource_group_name = optional(string)
    }), {})
  })
}

variable "private_endpoint" {
  description = "Where to place Private Endpoints (RG/location). Only required when private.enabled = true."
  type = object({
    resource_group_name = string
    location            = optional(string)
  })
  default = null
}
