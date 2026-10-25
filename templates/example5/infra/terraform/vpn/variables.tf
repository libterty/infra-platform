variable "client_vpn" {
  description = "Client VPN endpoint，選填。`null` 不建任何資源。`authentication` 至少給一種（`mutual_tls_root_certificate_arn`，或 module 外建好的 `saml_provider_arn`）；`associated_subnet_count` 是關聯幾個 data subnet（每個關聯另外按小時計費，1–2）；授權規則由 data subnet 的 CIDR 產生，只放行 data tier。連線 log 一律開啟。"
  type = object({
    server_certificate_arn = string
    authentication = object({
      mutual_tls_root_certificate_arn = optional(string)
      saml_provider_arn               = optional(string)
      self_service_saml_provider_arn  = optional(string)
    })
    client_cidr_block       = string
    associated_subnet_count = optional(number, 1)
    session_timeout_hours   = optional(number, 12)
    dns_servers             = optional(list(string), [])
    log_retention_days      = optional(number, 90)
  })
  default = null

  validation {
    condition     = var.client_vpn == null ? true : (var.client_vpn.associated_subnet_count >= 1 && var.client_vpn.associated_subnet_count <= 2 && floor(var.client_vpn.associated_subnet_count) == var.client_vpn.associated_subnet_count)
    error_message = "client_vpn.associated_subnet_count must be 1 or 2: the data tier has two subnets."
  }
}
