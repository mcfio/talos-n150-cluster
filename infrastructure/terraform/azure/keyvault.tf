/**
Create KeyVault for secrets and key management
**/
resource "azurerm_key_vault" "gitops-clusters-keyvault" {
  name                = "vault${random_id.random.dec}"
  resource_group_name = azurerm_resource_group.gitops-clusters.name
  location            = azurerm_resource_group.gitops-clusters.location
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name = "standard"
}

output "key_vault_name" {
  value = azurerm_key_vault.gitops-clusters-keyvault.name
}

resource "azurerm_key_vault_access_policy" "gitops-clusters-keyvault" {
  key_vault_id = azurerm_key_vault.gitops-clusters-keyvault.id

  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = data.azurerm_client_config.current.object_id

  key_permissions = [
    "get",
    "list",
    "update",
    "create",
    "import",
    "delete",
    "recover",
    "backup",
    "restore",
  ]

  secret_permissions = [
    "get",
    "list",
    "set",
    "delete",
    "recover",
    "backup",
    "restore",
  ]
}
