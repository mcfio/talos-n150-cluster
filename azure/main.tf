/**
Create the necessary Azure resources for the Cluster
**/

/**
* Generate a random 4 digit number
**/
resource "random_id" "random" {
  byte_length = 2
}

resource "azurerm_resource_group" "pi4-cluster" {
  name     = "pi4-cluster"
  location = "canadacentral"
}

resource "azurerm_storage_account" "pi4-cluster" {
  name                      = "storage${random_id.random.dec}"
  resource_group_name       = azurerm_resource_group.pi4-cluster.name
  location                  = azurerm_resource_group.pi4-cluster.location
  account_kind              = "StorageV2"
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  enable_https_traffic_only = true
}

resource "azurerm_storage_container" "prometheus-container" {
  name                  = "prometheus-object-storage"
  storage_account_name  = azurerm_storage_account.pi4-cluster.name
  container_access_type = "private"
}

/**
Create KeyVault for secrets and key management
**/
resource "azurerm_key_vault" "pi4-cluster-keyvault" {
  name                = "vault${random_id.random.dec}"
  resource_group_name = azurerm_resource_group.pi4-cluster.name
  location            = azurerm_resource_group.pi4-cluster.location
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name = "standard"
}

resource "azurerm_key_vault_access_policy" "pi4-cluster-keyvault" {
  key_vault_id = azurerm_key_vault.pi4-cluster-keyvault.id

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

/**
Create necessary permissions and key for the operation of Mozilla SOPS; https://github.com/mozilla/sops
**/
resource "azuread_application" "sops" {
  name = "vault${random_id.random.dec}-sops-sp"
  identifier_uris = [
    format("http://%s", "vault${random_id.random.dec}-sops-sp")
  ]
  available_to_other_tenants = false
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
  key_vault_id = azurerm_key_vault.pi4-cluster-keyvault.id
  key_type = "RSA"
  key_size = "4096"

  key_opts = [
    "encrypt",
    "decrypt",
  ]
}

resource "azurerm_key_vault_access_policy" "sops" {
  key_vault_id = azurerm_key_vault.pi4-cluster-keyvault.id

  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = azuread_service_principal.sops.id

  key_permissions = [
    "encrypt",
    "decrypt",
  ]
}
