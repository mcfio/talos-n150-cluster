resource "cloudflare_record" "domain_root" {
  zone_id = data.cloudflare_zone.domain.id
  name    = data.cloudflare_zone.domain.name
  value   = "ipv4.mcf.io"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "issuewild_caa" {
  zone_id = data.cloudflare_zone.domain.id
  name    = data.cloudflare_zone.domain.name
  type    = "CAA"

  data {
    flags = "0"
    tag   = "issuewild"
    value = "letsencrypt.org"
  }
}

resource "cloudflare_record" "issue_caa" {
  zone_id = data.cloudflare_zone.domain.id
  name    = data.cloudflare_zone.domain.name
  type    = "CAA"

  data {
    flags = "0"
    tag   = "issue"
    value = "letsencrypt.org"
  }
}

resource "cloudflare_record" "primary_mx" {
  zone_id  = data.cloudflare_zone.domain.id
  name     = data.cloudflare_zone.domain.name
  type     = "MX"
  priority = "0"
  value    = "mx01.mail.icloud.com"
}

resource "cloudflare_record" "secondary_mx" {
  zone_id  = data.cloudflare_zone.domain.id
  name     = data.cloudflare_zone.domain.name
  type     = "MX"
  priority = "10"
  value    = "mx02.mail.icloud.com"
}

resource "cloudflare_record" "spf_txt" {
  zone_id = data.cloudflare_zone.domain.id
  name    = data.cloudflare_zone.domain.name
  type    = "TXT"
  value   = "v=spf1 redirect=icloud.com"
}

resource "cloudflare_record" "dkim" {
  zone_id = data.cloudflare_zone.domain.id
  name    = "sig1._domainkey"
  type    = "CNAME"
  value   = "sig1.dkim.mcf.io.at.icloudmailadmin.com"
  proxied = false
}

resource "cloudflare_record" "azure_custom_domain" {
  zone_id = data.cloudflare_zone.domain.id
  name    = data.cloudflare_zone.domain.name
  type    = "TXT"
  value   = "MS=ms95064622"
}

module "milton_delegated_zone" {
  source = "./modules/cloudflare_delegation_record"

  zone_id = data.cloudflare_zone.domain.id
  name    = "milton.mcf.io"
  ttl     = 3600
  delegated_nameservers = [
    "ns1-09.azure-dns.com",
    "ns2-09.azure-dns.net",
    "ns3-09.azure-dns.org",
    "ns4-09.azure-dns.info"
  ]
}
