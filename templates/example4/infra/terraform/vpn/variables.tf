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

variable "site_to_site" {
  description = "Site-to-Site VPN，選填。`null` 不建任何資源。用 virtual private gateway（`amazon_side_asn` 沒給用 64512）接到這個 VPC，並對所有私有 route table 開 route propagation。`customer_gateway` 是地端設備（固定公網 IPv4，BGP 路由要給 `bgp_asn`）；`routing` 預設 BGP，改靜態路由要給 `static_routes_only` 與地端網段。pre-shared key 由服務存進 Secrets Manager，不經過 Terraform。"
  type = object({
    customer_gateway = object({
      ip_address  = string
      bgp_asn     = optional(number)
      device_name = optional(string)
    })
    routing = optional(object({
      static_routes_only = optional(bool, false)
      static_routes      = optional(list(string), [])
    }), {})
    amazon_side_asn    = optional(number)
    log_retention_days = optional(number, 90)
  })
  default = null
}
