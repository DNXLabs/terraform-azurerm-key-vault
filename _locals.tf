locals {
  prefix = var.name

  default_tags = {
    name      = var.name
    managedBy = "terraform"
  }

  tags = merge(local.default_tags, var.tags)

  rg_name = var.resource_group.create ? azurerm_resource_group.this[0].name : data.azurerm_resource_group.existing[0].name
  rg_loc  = var.resource_group.create ? azurerm_resource_group.this[0].location : data.azurerm_resource_group.existing[0].location

  # Key Vault name: alphanumeric only, 3-24 characters
  key_vault_name = substr(replace(lower(var.name), "/[^0-9a-z]/", ""), 0, 24)

  # Access model
  use_rbac         = lower(try(var.access.model, "rbac")) == "rbac"
  caller_object_id = data.azurerm_client_config.current.object_id

  private_enabled = try(var.private.enabled, false)

  dns_create_zone      = local.private_enabled && try(var.private.dns.create_zone, true)
  dns_create_vnet_link = local.private_enabled && try(var.private.dns.create_vnet_link, true)

  pe_subnet_id = try(var.private.pe_subnet_id, null)
  vnet_id      = try(var.private.vnet_id, null)

  # Private Link DNS zone for Key Vault
  pe_catalog = {
    vault = {
      subresource = "vault"
      zone_name   = "privatelink.vaultcore.azure.net"
      link_name   = "link-privatelink-vaultcore-azure-net"
    }
  }

  pe_services_enabled = local.private_enabled ? {
    for k, enabled in try(var.private.endpoints, {}) :
    k => merge(local.pe_catalog[k], {
      pe_name  = "pe-${local.key_vault_name}"
      psc_name = "psc-${local.key_vault_name}"
      nic_name = "nic-${local.key_vault_name}"
    })
    if enabled && contains(keys(local.pe_catalog), k)
  } : {}

  dns_cfg = try(var.private.dns, {})

  dns_rg_name_legacy = try(local.dns_cfg.resource_group_name, null)

  dns_rg_create = local.private_enabled && try(local.dns_cfg.resource_group.create, false)

  dns_rg_name = coalesce(
    try(local.dns_cfg.resource_group.name, null),
    local.dns_rg_name_legacy,
    local.rg_name
  )

  dns_rg_loc = coalesce(
    try(local.dns_cfg.resource_group.location, null),
    local.rg_loc
  )

  dns_resource_group_name = local.dns_rg_name

  dns_zone_exists = {
    for k, v in local.pe_services_enabled :
    k => length(try(data.azurerm_resources.private_dns_zones[k].resources, [])) > 0
  }

  dns_zone_id_existing = {
    for k, v in local.pe_services_enabled :
    k => local.dns_zone_exists[k] ? data.azurerm_resources.private_dns_zones[k].resources[0].id : null
  }

  dns_zone_should_create = {
    for k, v in local.pe_services_enabled :
    k => local.dns_create_zone
  }

  vnet_link_exists = {
    for k, v in local.pe_services_enabled :
    k => length(try(data.azurerm_resources.private_dns_vnet_links[k].resources, [])) > 0
  }

  vnet_link_should_create = {
    for k, v in local.pe_services_enabled :
    k => local.dns_create_vnet_link
  }

  private_dns_zone_id = {
    for k, v in local.pe_services_enabled :
    k => local.dns_zone_exists[k]
      ? local.dns_zone_id_existing[k]
      : try(azurerm_private_dns_zone.this[k].id, null)
  }

  pe_rg_name = local.private_enabled ? var.private_endpoint.resource_group_name : null
  pe_rg_loc  = local.private_enabled ? coalesce(try(var.private_endpoint.location, null), local.rg_loc) : null

  diag_enabled = try(var.diagnostics.enabled, false) && (try(var.diagnostics.log_analytics_workspace_id, null) != null || try(var.diagnostics.storage_account_id, null) != null || try(var.diagnostics.eventhub_authorization_rule_id, null) != null)
}
