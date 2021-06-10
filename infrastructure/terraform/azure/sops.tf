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

resource "time_rotating" "sops" {
  rotation_years = "2"

  triggers = {
    years = "2"
  }
}

resource "random_password" "sops" {
  length = 32

  keepers = {
    rfc3339 = time_rotating.sops.id
  }
}

resource "azuread_service_principal" "sops" {
  application_id = azuread_application.sops.application_id
}

resource "azuread_service_principal_password" "sops" {
  service_principal_id = azuread_service_principal.sops.id
  value                = random_password.sops.result
  end_date             = time_rotating.sops.rotation_rfc3339
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

  depends_on = [
    azurerm_key_vault_access_policy.gitops-clusters-keyvault
  ]
}

resource "azurerm_key_vault_access_policy" "sops" {
  key_vault_id = azurerm_key_vault.gitops-clusters-keyvault.id

  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = azuread_service_principal.sops.id

  key_permissions = [
    "encrypt",
    "decrypt",
  ]

  depends_on = [
    azurerm_key_vault_access_policy.gitops-clusters-keyvault
  ]
}
