provider "azurerm" {
  version = "=2.62.1"
  features {}
}
provider "azuread" { version = "1.0.0" }
provider "random" { version = "3.0.0" }
provider "time" { version = "0.6.0" }

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}
