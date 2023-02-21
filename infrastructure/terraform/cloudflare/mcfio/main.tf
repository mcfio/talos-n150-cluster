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
      version = ">= 3.34.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

data "cloudflare_zone" "domain" {
  zone_id = var.cloudflare_zone_id
}
