data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "existing" {
  count = var.resource_group.create ? 0 : 1
  name  = var.resource_group.name
}

data "azurerm_resource_group" "dns" {
  count = (!local.dns_rg_create && local.private_enabled) ? 1 : 0
  name  = local.dns_rg_name
}

data "azurerm_resources" "private_dns_zones" {
  for_each = (!local.dns_rg_create && local.private_enabled) ? local.pe_services_enabled : {}

  resource_group_name = local.dns_rg_name
  type                = "Microsoft.Network/privateDnsZones"
  name                = each.value.zone_name

  depends_on = [
    data.azurerm_resource_group.dns
  ]
}

data "azurerm_resources" "private_dns_vnet_links" {
  for_each = (!local.dns_rg_create && local.private_enabled) ? local.pe_services_enabled : {}

  resource_group_name = local.dns_rg_name
  type                = "Microsoft.Network/privateDnsZones/virtualNetworkLinks"
  name                = each.value.link_name

  depends_on = [
    data.azurerm_resource_group.dns
  ]
}
