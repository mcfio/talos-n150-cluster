terraform {
  cloud {
    organization = "mcfaul-cloud"
    hostname     = "app.terraform.io"

    workspaces {
      name = "cloudflare-mcfio"
    }
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
  required_version = "~> 1.3"
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

data "cloudflare_zone" "domain" {
  zone_id = var.cloudflare_zone_id
}
