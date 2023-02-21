# Cloudflare Delegation Record Type

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 3.34.0"
    }
  }
  required_version = ">= 1.3.0"
}

resource "cloudflare_record" "milton_delegated_zone" {
  count = length(var.delegated_nameservers)

  zone_id = var.zone_id
  name    = var.name
  type    = "NS"
  value   = element(var.delegated_nameservers, count.index)
}
