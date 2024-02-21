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

output "vault_name" {
  value = azurerm_key_vault.gitops-clusters-keyvault.name
}

resource "azurerm_key_vault_access_policy" "gitops-clusters-keyvault" {
  key_vault_id = azurerm_key_vault.gitops-clusters-keyvault.id

  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Get",
    "List",
    "Update",
    "Create",
    "Import",
    "Delete",
    "Recover",
    "Backup",
    "Restore",
  ]

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Recover",
    "Backup",
    "Restore",
  ]
}
