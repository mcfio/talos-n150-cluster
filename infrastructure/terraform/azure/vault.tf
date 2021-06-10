resource "azuread_application" "vault" {
  display_name     = "vault${random_id.random.dec}-vault-sp"
  identifier_uris  = [format("http://%s", "vault${random_id.random.dec}-vault-sp")]
  owners           = [data.azurerm_client_config.current.object_id]
  sign_in_audience = "AzureADMyOrg"
}

output "vault_client_id" {
  value = azuread_application.vault.application_id
}

resource "azuread_service_principal" "vault" {
  application_id = azuread_application.vault.application_id
}

resource "azuread_service_principal_password" "vault" {
  service_principal_id = azuread_service_principal.vault.object_id
}

output "vault_client_secret" {
  value     = azuread_service_principal_password.vault.value
  sensitive = true
}

resource "azurerm_key_vault_access_policy" "vault" {
  key_vault_id = azurerm_key_vault.gitops-clusters-keyvault.id

  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = azuread_service_principal.vault.id

  key_permissions = [
    "Get",
    "WrapKey",
    "UnwrapKey",
  ]

  depends_on = [
    azurerm_key_vault_access_policy.gitops-clusters-keyvault
  ]
}

resource "azurerm_key_vault_key" "milton-cluster" {
  name         = "milton-cluster-unseal-key"
  key_vault_id = azurerm_key_vault.gitops-clusters-keyvault.id
  key_type     = "RSA"
  key_size     = 3072

  key_opts = [
    "wrapKey",
    "unwrapKey",
  ]
}
