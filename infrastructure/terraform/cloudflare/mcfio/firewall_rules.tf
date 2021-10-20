
# GeoIP Blocking
resource "cloudflare_filter" "restricted_countries" {
  zone_id     = data.cloudflare_zone.domain.id
  description = "Expression to block all countries except US, CA, UK and AU"
  expression  = "(not ip.geoip.country in {\"US\" \"CA\" \"AU\" \"GB\"})"
}

resource "cloudflare_firewall_rule" "restricted_countries" {
  zone_id     = data.cloudflare_zone.domain.id
  description = "Firewall rule to block all countries except US, CA, UK and AU"
  filter_id   = cloudflare_filter.restricted_countries.id
  action      = "block"
}

# Bot Blocking
resource "cloudflare_filter" "restrict_bots" {
  zone_id     = data.cloudflare_zone.domain.id
  description = "Expression to block bots as determined by CF"
  expression  = "(cf.client.bot)"
}

resource "cloudflare_firewall_rule" "restrict_bots" {
  zone_id     = data.cloudflare_zone.domain.id
  description = "Firewall rule to block bots as determined by CF"
  filter_id   = cloudflare_filter.restrict_bots.id
  action      = "block"
}

# Threat Blocking
resource "cloudflare_filter" "restrict_threats" {
  zone_id     = data.cloudflare_zone.domain.id
  description = "Expression to block medium threats"
  expression  = "(cf.threat_score gt 14)"
}

resource "cloudflare_firewall_rule" "restrict_threats" {
  zone_id     = data.cloudflare_zone.domain.id
  description = "Firewall rule to block medium threats"
  filter_id   = cloudflare_filter.restrict_threats.id
  action      = "block"
}
