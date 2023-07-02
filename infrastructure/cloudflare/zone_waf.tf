
resource "cloudflare_ruleset" "ruleset" {
  kind    = "zone"
  name    = "home-cluster-ruleset"
  phase   = "http_request_firewall_custom"
  zone_id = data.cloudflare_zone.domain.id

  # GeoIP Blocking
  rules {
    action      = "block"
    description = "Firewall rule to block all countries except US, CA, UK and AU"
    enabled     = true
    expression  = "(not ip.geoip.country in {\"US\" \"CA\" \"AU\" \"GB\"})"
  }

  # Bot & Threat Blocking
  rules {
    action      = "block"
    description = "Firewall rule to block bots and threats as determined by CF"
    enabled     = true
    expression  = "(cf.client.bot) or (cf.threat_score gt 14)"
  }
}
