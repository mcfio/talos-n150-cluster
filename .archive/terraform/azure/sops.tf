/**
Create necessary permissions and key for the operation of Mozilla SOPS; https://github.com/mozilla/sops
**/
resource "azuread_application" "sops" {
  display_name = "vault${random_id.random.dec}-sops-sp"
  identifier_uris = [
    format("http://%s", "vault${random_id.random.dec}-sops-sp")
  ]
  sign_in_audience = "AzureADMyOrg"
}

output "sops_client_id" {
  value = azuread_application.sops.application_id
}

resource "azuread_service_principal" "sops" {
  application_id = azuread_application.sops.application_id
}

resource "azuread_service_principal_password" "sops" {
  service_principal_id = azuread_service_principal.sops.id
}

output "sops_client_secret" {
  value     = azuread_service_principal_password.sops.value
  sensitive = true
}

resource "azurerm_key_vault_key" "sops" {
  name         = "sops-key"
  key_vault_id = azurerm_key_vault.gitops-clusters-keyvault.id
  key_type     = "RSA"
  key_size     = "4096"

  key_opts = [
    "encrypt",
    "decrypt",
  ]
}

resource "azurerm_role_assignment" "sops" {
  scope = azurerm_key_vault.gitops-clusters-keyvault.id
  principal_id = azuread_service_principal.sops.id
  role_definition_name = "Key Vault Crypto User"
}

resource "azurerm_key_vault_access_policy" "sops" {
  key_vault_id = azurerm_key_vault.gitops-clusters-keyvault.id

  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = azuread_service_principal.sops.id

  key_permissions = [
    "encrypt",
    "decrypt",
  ]
}
