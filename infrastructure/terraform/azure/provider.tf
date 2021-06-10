terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
}
provider "azurerm" {
  features {}
}
provider "azuread" {}
provider "random" {}
provider "time" {}

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}
