resource "azurerm_resource_group" "this" {
  count    = var.resource_group.create ? 1 : 0
  name     = var.resource_group.name
  location = var.resource_group.location
  tags     = local.tags
}

resource "azurerm_resource_group" "dns" {
  count    = local.dns_rg_create ? 1 : 0
  name     = local.dns_rg_name
  location = local.dns_rg_loc
  tags     = local.tags
}

resource "azurerm_key_vault" "this" {
  name                = local.key_vault_name
  location            = local.rg_loc
  resource_group_name = local.rg_name

  tenant_id = coalesce(try(var.key_vault.tenant_id, null), data.azurerm_client_config.current.tenant_id)
  sku_name  = try(var.key_vault.sku_name, "standard")

  rbac_authorization_enabled = local.use_rbac

  purge_protection_enabled      = try(var.key_vault.purge_protection_enabled, false) # Default to false for easy cleanup
  soft_delete_retention_days    = try(var.key_vault.soft_delete_retention_days, 7)
  public_network_access_enabled = try(var.key_vault.public_network_access_enabled, false)

  dynamic "network_acls" {
    for_each = try(var.key_vault.network_acls, null) != null ? [var.key_vault.network_acls] : []
    content {
      bypass                     = try(network_acls.value.bypass, "AzureServices")
      default_action             = try(network_acls.value.default_action, "Allow")
      ip_rules                   = try(network_acls.value.ip_rules, [])
      virtual_network_subnet_ids = try(network_acls.value.virtual_network_subnet_ids, [])
    }
  }

  tags = local.tags
}

resource "azurerm_role_assignment" "caller" {
  count = local.use_rbac ? 1 : 0

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = local.caller_object_id
}

resource "azurerm_role_assignment" "additional" {
  for_each = local.use_rbac ? toset(try(var.access.additional_object_ids, [])) : toset([])

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value
}

resource "azurerm_key_vault_access_policy" "caller" {
  count = local.use_rbac ? 0 : 1

  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = local.caller_object_id

  key_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Import", "Backup", "Restore", "Recover", "Purge"
  ]
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Backup", "Restore", "Recover", "Purge"
  ]
  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Import", "ManageContacts", "ManageIssuers",
    "GetIssuers", "ListIssuers", "SetIssuers", "DeleteIssuers", "Backup", "Restore", "Recover", "Purge"
  ]
}

resource "azurerm_key_vault_access_policy" "additional" {
  for_each = local.use_rbac ? tomap({}) : { for id in try(var.access.additional_object_ids, []) : id => id }

  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = each.value

  key_permissions    = ["Get", "List", "Create", "Delete", "Update", "Import", "Backup", "Restore", "Recover", "Purge"]
  secret_permissions = ["Get", "List", "Set", "Delete", "Backup", "Restore", "Recover", "Purge"]
  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Import", "ManageContacts", "ManageIssuers",
    "GetIssuers", "ListIssuers", "SetIssuers", "DeleteIssuers", "Backup", "Restore", "Recover", "Purge"
  ]
}

resource "azurerm_private_dns_zone" "this" {
  for_each = { for k, v in local.pe_services_enabled : k => v if local.dns_zone_should_create[k] }

  name                = each.value.zone_name
  resource_group_name = local.dns_rg_name
  tags                = local.tags
  depends_on = [
    azurerm_resource_group.dns
  ]
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = { for k, v in local.pe_services_enabled : k => v if local.vnet_link_should_create[k] }

  name                = each.value.link_name
  resource_group_name = local.dns_rg_name

  private_dns_zone_name = coalesce(
    try(azurerm_private_dns_zone.this[each.key].name, null),
    each.value.zone_name
  )

  virtual_network_id = local.vnet_id
  tags               = local.tags

  depends_on = [
    azurerm_resource_group.dns,
    azurerm_private_dns_zone.this
  ]
}

resource "azurerm_private_endpoint" "this" {
  for_each            = local.pe_services_enabled
  name                = each.value.pe_name
  location            = local.pe_rg_loc
  resource_group_name = local.pe_rg_name
  subnet_id                     = local.pe_subnet_id
  custom_network_interface_name = each.value.nic_name

  tags                = local.tags

  private_service_connection {
    name                           = each.value.psc_name
    private_connection_resource_id = azurerm_key_vault.this.id
    is_manual_connection           = false
    subresource_names              = [each.value.subresource]
  }

  private_dns_zone_group {
    name                 = "pdzg-${each.key}"
    private_dns_zone_ids = [local.private_dns_zone_id[each.key]]
  }
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = local.diag_enabled ? 1 : 0

  name                           = "diag-${local.key_vault_name}"
  target_resource_id             = azurerm_key_vault.this.id
  log_analytics_workspace_id     = try(var.diagnostics.log_analytics_workspace_id, null)
  storage_account_id             = try(var.diagnostics.storage_account_id, null)
  eventhub_authorization_rule_id = try(var.diagnostics.eventhub_authorization_rule_id, null)

  enabled_log { category = "AuditEvent" }
  enabled_log { category = "AzurePolicyEvaluationDetails" }

  enabled_metric {
    category = "AllMetrics"
  }
}
