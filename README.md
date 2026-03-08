# terraform-azurerm-key-vault

Terraform module for creating and managing Azure Key Vaults with support for both Azure RBAC and Vault Access Policy models, private endpoints with automatic DNS zone management, and optional diagnostic settings.

This module automatically grants the deploying identity full access to the Key Vault and supports adding additional principals for multi-team environments.

## Features

- **Dual Access Models**: Azure RBAC (default) or legacy Vault Access Policies
- **Auto-Caller Access**: Automatically grants the Terraform caller access to the Key Vault
- **Additional Principals**: Add extra object IDs for team members or service principals
- **Private Endpoints**: Automatic private endpoint creation for vault service
- **Private DNS Zones**: Automatic creation and management of private DNS zones
- **DNS Zone Auto-Discovery**: Reuses existing DNS zones when available
- **Network ACLs**: Optional network access rules with service bypass
- **Diagnostic Settings**: Optional Azure Monitor integration (Log Analytics, Storage, Event Hub)
- **Resource Group Flexibility**: Create new or use existing resource groups
- **Tagging Strategy**: Built-in default tagging with custom tag support
- **Purge Protection**: Configurable purge protection and soft-delete retention

## Usage

### Example 1 — Non-Prod (Public Access with RBAC)

A simple Key Vault with public access enabled and Azure RBAC for development environments.

```hcl
module "keyvault" {
  source = "./modules/keyvault"

  name = "mycompany-dev-aue-app"

  resource_group = {
    create   = true
    name     = "rg-mycompany-dev-aue-app-001"
    location = "australiaeast"
  }

  tags = {
    project     = "my-app"
    environment = "development"
  }

  key_vault = {
    sku_name                      = "standard"
    public_network_access_enabled = true
    purge_protection_enabled      = false
    soft_delete_retention_days    = 7
  }

  access = {
    model = "rbac"
  }

  private = {
    enabled = false
  }
}
```

### Example 2 — Production (Private, RBAC, Multiple Principals)

A production Key Vault with private endpoints, RBAC model, and multiple team principals.

```hcl
module "keyvault" {
  source = "./modules/keyvault"

  name = "contoso-prod-aue-secrets"

  resource_group = {
    create   = true
    name     = "rg-contoso-prod-aue-secrets-001"
    location = "australiaeast"
  }

  tags = {
    project     = "secrets-management"
    environment = "production"
    compliance  = "soc2"
  }

  key_vault = {
    sku_name                      = "premium"
    public_network_access_enabled = false
    purge_protection_enabled      = true
    soft_delete_retention_days    = 90

    network_acls = {
      bypass         = "AzureServices"
      default_action = "Deny"
    }
  }

  access = {
    model = "rbac"
    additional_object_ids = [
      "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",  # Platform team
      "ffffffff-1111-2222-3333-444444444444",    # App team service principal
    ]
  }

  private = {
    enabled = true

    endpoints = {
      vault = true
    }

    pe_subnet_id = "/subscriptions/xxxx/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-pe"
    vnet_id      = "/subscriptions/xxxx/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-prod"

    dns = {
      create_zone      = true
      create_vnet_link = true

      resource_group = {
        create   = false
        name     = "rg-contoso-prod-aue-dns-001"
      }
    }
  }

  private_endpoint = {
    resource_group_name = "rg-contoso-prod-aue-network-001"
    location            = "australiaeast"
  }

  diagnostics = {
    enabled                    = true
    log_analytics_workspace_id = "/subscriptions/xxxx/resourceGroups/rg-monitor/providers/Microsoft.OperationalInsights/workspaces/law-prod"
  }
}
```

### Using YAML Variables

Create a `vars/platform.yaml` file:

```yaml
azure:
  subscription_id: "afb35bd4-145f-4a15-889e-5da052d030ce"
  location: australiaeast

network_lookup:
  resource_group_name: "rg-managed-services-lab-aue-stg-001"
  vnet_name: "vnet-managed-services-lab-aue-stg-001"
  pe_subnet_name: "snet-stg-pe"

platform:
  keyvaults:
    secrets:
      naming:
        org: managed-services
        env: lab
        region: aue
        workload: stg

      resource_group:
        create: true
        name: "rg-keyvault-lab-aue-stg-001"
        location: australiaeast

      key_vault:
        sku_name: standard
        public_network_access_enabled: false
        purge_protection_enabled: false
        soft_delete_retention_days: 7

      access:
        model: rbac

      private:
        enabled: true
        endpoints:
          vault: true
        dns:
          create_zone: true
          create_vnet_link: true
          resource_group:
            create: true
            name: "rg-dns-services-lab-aue-001"
            location: australiaeast
```

Then use in your Terraform:

```hcl
locals {
  workspace = yamldecode(file("vars/${terraform.workspace}.yaml"))
}

data "azurerm_resource_group" "network" {
  name = local.workspace.network_lookup.resource_group_name
}

data "azurerm_virtual_network" "this" {
  name                = local.workspace.network_lookup.vnet_name
  resource_group_name = data.azurerm_resource_group.network.name
}

data "azurerm_subnet" "pe" {
  name                 = local.workspace.network_lookup.pe_subnet_name
  virtual_network_name = data.azurerm_virtual_network.this.name
  resource_group_name  = data.azurerm_resource_group.network.name
}

module "keyvault" {
  for_each = try(local.workspace.platform.keyvaults, {})

  source = "./modules/keyvault"

  name           = "${each.value.naming.org}-${each.value.naming.env}-${each.value.naming.region}-${each.value.naming.workload}"
  resource_group = each.value.resource_group
  tags           = try(each.value.tags, {})

  key_vault = each.value.key_vault
  access    = try(each.value.access, {})

  private = merge(
    try(each.value.private, { enabled = false }),
    try(each.value.private, {}).enabled == true ? {
      pe_subnet_id = data.azurerm_subnet.pe.id
      vnet_id      = data.azurerm_virtual_network.this.id
    } : {}
  )

  private_endpoint = try(each.value.private, {}).enabled == true ? {
    resource_group_name = data.azurerm_resource_group.network.name
    location            = data.azurerm_resource_group.network.location
  } : null

  diagnostics = try(each.value.diagnostics, {})
}
```

## Access Models

### Azure RBAC (Default, Recommended)

Uses Azure Role-Based Access Control. The module assigns `Key Vault Secrets Officer` to the deploying identity.

```hcl
access = {
  model = "rbac"
  additional_object_ids = ["<object-id-1>", "<object-id-2>"]
}
```

### Vault Access Policy (Legacy)

Uses legacy access policies with full key, secret, and certificate permissions.

```hcl
access = {
  model = "vault_access_policy"
  additional_object_ids = ["<object-id-1>"]
}
```

## Private Endpoints

### Supported Services

The module supports private endpoints for:
- **vault**: Key Vault (`privatelink.vaultcore.azure.net`)

### DNS Zone Management

```hcl
# Auto-create DNS zones
dns = {
  create_zone      = true
  create_vnet_link = true
  resource_group = {
    create   = false
    name     = "rg-shared-dns"
  }
}

# Use existing DNS zones
dns = {
  create_zone      = false
  create_vnet_link = false
  resource_group = {
    create = false
    name   = "rg-shared-dns"
  }
}
```

## Naming Convention

Key Vault names must be globally unique, between 3-24 characters.

The module generates names based on the prefix:
```
kv-{name}-{suffix}
```

Example: `kv-contoso-prod-aue-secrets-001`

## Outputs

| Name | Description |
|------|-------------|
| `resource_group_name` | Resource Group where the Key Vault is deployed |
| `key_vault` | Key Vault object with id, name, vault_uri, location |
| `resource` | Generic resource output (id, name, type) |
| `private_endpoints` | Private endpoints associated with the Key Vault |
| `private_dns_zone_ids` | Private DNS Zone IDs |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| azurerm | >= 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | >= 4.0.0 |

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `name` | Resource name prefix for all resources | string | yes |
| `resource_group` | Resource group configuration | object | yes |
| `key_vault` | Key Vault configuration (SKU, purge protection, network ACLs) | object | yes |
| `private` | Private endpoint configuration | object | yes |
| `tags` | Extra tags merged with default tags | map(string) | no |
| `access` | Access model configuration (RBAC or Vault Access Policy) | object | no |
| `private_endpoint` | Private endpoint resource group placement | object | no |
| `diagnostics` | Azure Monitor diagnostic settings | object | no |

### Detailed Input Specifications

#### key_vault

```hcl
object({
  name        = optional(string)
  name_suffix = optional(string, "001")

  sku_name = optional(string, "standard")  # standard | premium

  tenant_id = optional(string)  # Auto-detected from caller

  purge_protection_enabled   = optional(bool, true)
  soft_delete_retention_days = optional(number, 7)

  public_network_access_enabled = optional(bool, false)

  network_acls = optional(object({
    bypass                     = optional(string, "AzureServices")
    default_action             = optional(string, "Deny")
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  }))
})
```

#### access

```hcl
object({
  model                 = optional(string, "rbac")  # rbac | vault_access_policy
  additional_object_ids = optional(list(string), [])
})
```

#### private

```hcl
object({
  enabled = bool

  endpoints = optional(map(bool), {
    vault = true
  })

  pe_subnet_id = optional(string)  # Required if enabled = true
  vnet_id      = optional(string)  # Required if enabled = true

  dns = optional(object({
    create_zone      = optional(bool, true)
    create_vnet_link = optional(bool, true)
    resource_group = optional(object({
      create   = bool
      name     = string
      location = optional(string)
    }))
  }), {})
})
```

## Best Practices

1. **Use RBAC**: Prefer Azure RBAC over Vault Access Policies for better governance
2. **Enable Purge Protection**: Always enable in production (note: cannot be disabled once enabled)
3. **Private Endpoints**: Use private endpoints for all production Key Vaults
4. **Network ACLs**: Restrict access to trusted networks and Azure services
5. **Premium SKU**: Use `premium` for HSM-backed keys when required by compliance
6. **Soft Delete**: Set appropriate retention period (7-90 days)
7. **Diagnostics**: Enable audit logging for compliance and security monitoring

## License

Apache 2.0 Licensed. See LICENSE for full details.

## Authors

Module managed by DNX Solutions.

## Contributing

Please read CONTRIBUTING.md for details on our code of conduct and the process for submitting pull requests.
