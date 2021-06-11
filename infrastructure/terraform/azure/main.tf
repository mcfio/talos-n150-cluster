/**
Create the necessary Azure resources for the Cluster
**/

/**
* Generate a random 4 digit number
**/
resource "random_id" "random" {
  byte_length = 2
}

resource "azurerm_resource_group" "gitops-clusters" {
  name     = "GitOps-Clusters"
  location = "canadacentral"
}

resource "azurerm_storage_account" "gitops-clusters" {
  name                      = "storage${random_id.random.dec}"
  resource_group_name       = azurerm_resource_group.gitops-clusters.name
  location                  = azurerm_resource_group.gitops-clusters.location
  account_kind              = "StorageV2"
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  enable_https_traffic_only = true
}

output "storage_account_name" {
  value = azurerm_storage_account.gitops-clusters.name
}

resource "azurerm_storage_container" "metrics-container" {
  name                  = "metrics-object-storage"
  storage_account_name  = azurerm_storage_account.gitops-clusters.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "logs-container" {
  name                  = "logs-object-storage"
  storage_account_name  = azurerm_storage_account.gitops-clusters.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "backups-container" {
  name                  = "backups-object-storage"
  storage_account_name  = azurerm_storage_account.gitops-clusters.name
  container_access_type = "private"
}
