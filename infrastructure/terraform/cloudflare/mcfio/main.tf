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

variable "cloudflare_email" {
  type = string
}
variable "cloudflare_api_key" {
  type = string
}

provider "cloudflare" {
  email   = var.cloudflare_email
  api_key = var.cloudflare_api_key
}

data "cloudflare_zone" "domain" {
  zone_id = "73816e78e046d700ba68abfa82efd565"
}

resource "cloudflare_page_rule" "page_rules_for_plex" {
  zone_id  = data.cloudflare_zone.domain.id
  target   = "plex.mcf.io/*"
  status   = "active"
  priority = 1

  actions {
    cache_level = "bypass"
  }
}
