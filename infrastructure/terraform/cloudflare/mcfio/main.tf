terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "mcfaul-cloud"

    workspaces {
      name = "cloudflare-mcfio"
    }
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 3.2"
    }
  }
}

variable "cloudflare_email" {}
variable "cloudflare_api_key" {}

provider "cloudflare" {
  email   = var.cloudflare_email
  api_key = var.cloudflare_api_key
}

data "cloudflare_zone" "domain" {
  zone_id = "73816e78e046d700ba68abfa82efd565"
}
