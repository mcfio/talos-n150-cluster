# --
# Required Parameters
# --

variable "cloudflare_api_token" {
  description = "The API Token for operations. See: https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs#api_token"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "The zone identifier to target for the resource."
  type        = string
}
