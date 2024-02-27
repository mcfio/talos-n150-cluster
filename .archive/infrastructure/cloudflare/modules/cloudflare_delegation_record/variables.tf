# --
# Required Parameters
# --

variable "zone_id" {
  description = "The zone identifier to target for the resource. See: https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/record#zone_id"
  type        = string
}

variable "name" {
  description = "The name of the record. See: https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/record#name"
  type        = string
}

variable "ttl" {
  description = "The TTL of the record. See: https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/record#ttl"
  type        = number
  default     = 3600 # Sets default to 1hr, 1 == Auto
}

variable "delegated_nameservers" {
  description = "List of name servers to configure as zone delegation"
  type        = list(string)
  default     = []
}
