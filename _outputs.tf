output "resource_group_name" {
  description = "Resource Group where the Key Vault is deployed."
  value       = local.rg_name
}

output "key_vault" {
  description = "Key Vault main outputs for RBAC and integrations."
  value = {
    id        = azurerm_key_vault.this.id
    name      = azurerm_key_vault.this.name
    vault_uri = azurerm_key_vault.this.vault_uri
    location  = azurerm_key_vault.this.location
  }
}

output "resource" {
  description = "Generic resource output (standardized across platform modules)."
  value = {
    id   = azurerm_key_vault.this.id
    name = azurerm_key_vault.this.name
    type = "Microsoft.KeyVault/vaults"
  }
}

output "private_endpoints" {
  description = "Private Endpoints associated with the Key Vault (empty if private is disabled)."
  value = {
    for k, pe in azurerm_private_endpoint.this :
    k => {
      id                 = pe.id
      name               = pe.name
      private_ip_address = try(pe.private_service_connection[0].private_ip_address, null)
      subnet_id           = pe.subnet_id
    }
  }
}

output "private_dns_zone_ids" {
  description = "Private DNS Zone IDs associated with the Key Vault (empty if private is disabled)."
  value = {
    for k, v in local.pe_services_enabled :
    k => local.private_dns_zone_id[k]
  }
}
