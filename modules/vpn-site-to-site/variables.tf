variable "name" {
  type        = string
  description = "VPN 連線的名稱，也是各資源的 `Name` tag 與 log group 名稱的一部分。2–63 字元，限小寫英數字與 `-`，以字母開頭。"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.name))
    error_message = "name must be lowercase letters, digits or hyphens, starting with a letter (2-63 characters)."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "module 自己建的 tunnel log group 加密用的客戶管理 KMS key ARN（symmetric），必填。key policy 要讓 CloudWatch Logs（`logs.<region>.amazonaws.com`）能使用這把 key。pre-shared key 由 Site-to-Site VPN 服務存進它自己管理的 Secrets Manager secret，不經過這把 key，也不經過 Terraform。"

  validation {
    condition     = var.kms_key_arn != null && can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "vpn_gateway" {
  type = object({
    amazon_side_asn = optional(number)
  })
  default     = null
  description = "要 module 自己建 virtual private gateway（VGW）並掛到 `vpc_id` 時給，`{}` 表示用預設 ASN 64512。`amazon_side_asn` 是 AWS 這一側的私有 BGP ASN：16 位元 64512–65534，或 32 位元 4200000000–4294967294。跟 `transit_gateway_id` 恰好擇一。"

  validation {
    condition = var.vpn_gateway == null ? true : (
      var.vpn_gateway.amazon_side_asn == null ? true : (
        (var.vpn_gateway.amazon_side_asn >= 64512 && var.vpn_gateway.amazon_side_asn <= 65534) ||
        (var.vpn_gateway.amazon_side_asn >= 4200000000 && var.vpn_gateway.amazon_side_asn <= 4294967294)
      )
    )
    error_message = "vpn_gateway.amazon_side_asn must be a private ASN: 64512-65534 or 4200000000-4294967294."
  }

  validation {
    condition     = (var.vpn_gateway == null) != (var.transit_gateway_id == null)
    error_message = "Set exactly one of vpn_gateway (module-created virtual private gateway) and transit_gateway_id (existing transit gateway)."
  }
}

variable "transit_gateway_id" {
  type        = string
  default     = null
  description = "既有 transit gateway 的 ID（`tgw-0123456789abcdef0`），VPN 連線直接終結在它上面。跟 `vpn_gateway` 恰好擇一；transit gateway 本身與它的 route table 不歸這個 module 管。"

  validation {
    condition     = var.transit_gateway_id == null ? true : can(regex("^tgw-[0-9a-f]{8,17}$", var.transit_gateway_id))
    error_message = "transit_gateway_id must look like tgw-0123456789abcdef0."
  }
}

variable "vpc_id" {
  type        = string
  default     = null
  description = "VGW 要掛上去的 VPC，格式 `vpc-0123456789abcdef0`。給了 `vpn_gateway` 就必填；用 `transit_gateway_id` 時必須是 `null`。"

  validation {
    condition     = var.vpc_id == null ? true : can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must look like vpc-0123456789abcdef0."
  }

  validation {
    condition     = var.vpn_gateway == null || var.vpc_id != null
    error_message = "vpc_id is required when vpn_gateway is set; the virtual private gateway is attached to that VPC."
  }

  validation {
    condition     = var.vpn_gateway != null || var.vpc_id == null
    error_message = "vpc_id must be null with transit_gateway_id; the transit gateway has its own VPC attachments."
  }
}

variable "customer_gateway" {
  type = object({
    ip_address  = string
    bgp_asn     = optional(number)
    device_name = optional(string)
  })
  description = "地端 VPN 設備。`ip_address` 是設備對外介面的固定公網 IPv4（在 NAT 後面就填 NAT 的位址）；`bgp_asn` 是地端的 BGP ASN，1–4294967295（不可用 7224），BGP 路由必填，靜態路由可以是 `null`；`device_name` 是選填的設備名稱。不支援憑證型 customer gateway。"

  validation {
    condition     = can(regex("^((25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])$", var.customer_gateway.ip_address))
    error_message = "customer_gateway.ip_address must be an IPv4 address such as 198.51.100.10."
  }

  validation {
    condition     = var.customer_gateway.bgp_asn == null ? true : (var.customer_gateway.bgp_asn >= 1 && var.customer_gateway.bgp_asn <= 4294967295 && floor(var.customer_gateway.bgp_asn) == var.customer_gateway.bgp_asn)
    error_message = "customer_gateway.bgp_asn must be an integer between 1 and 4294967295."
  }

  validation {
    condition     = var.customer_gateway.bgp_asn != 7224
    error_message = "customer_gateway.bgp_asn must not be 7224; AWS reserves it in all Regions."
  }
}

variable "routing" {
  type = object({
    static_routes_only = optional(bool, false)
    static_routes      = optional(list(string), [])
  })
  default     = {}
  nullable    = false
  description = "路由方式。預設 `{}` 是 BGP（動態），這時 `customer_gateway.bgp_asn` 必填。`static_routes_only = true` 用靜態路由：VGW 模式要在 `static_routes` 列出地端網段（網路位址格式，例如 `192.168.10.0/24`，最多 100 條，不可為 `0.0.0.0/0`）；transit gateway 模式的靜態路由放在 transit gateway 的 route table，這裡不能給。"

  validation {
    condition     = var.routing.static_routes_only || length(var.routing.static_routes) == 0
    error_message = "static_routes needs static_routes_only = true; a BGP connection learns its routes from the customer gateway."
  }

  validation {
    condition     = !var.routing.static_routes_only || var.transit_gateway_id != null || length(var.routing.static_routes) > 0
    error_message = "A static connection on a virtual private gateway needs at least one static route."
  }

  validation {
    condition     = var.transit_gateway_id == null || length(var.routing.static_routes) == 0
    error_message = "static_routes is not supported with transit_gateway_id; add static routes to the transit gateway route table instead."
  }

  validation {
    condition     = var.routing.static_routes_only || var.customer_gateway.bgp_asn != null
    error_message = "BGP routing needs customer_gateway.bgp_asn; set routing.static_routes_only = true for a device without BGP."
  }

  validation {
    condition     = alltrue([for c in var.routing.static_routes : can(cidrnetmask(c)) ? cidrsubnet(c, 0, 0) == c : false])
    error_message = "static_routes must be IPv4 network addresses such as 192.168.10.0/24."
  }

  validation {
    condition     = !contains(var.routing.static_routes, "0.0.0.0/0")
    error_message = "static_routes must not contain 0.0.0.0/0; route only the on-premises networks."
  }

  validation {
    condition     = length(distinct(var.routing.static_routes)) == length(var.routing.static_routes) && length(var.routing.static_routes) <= 100
    error_message = "static_routes must not contain duplicates and may hold at most 100 routes (AWS quota)."
  }
}

variable "propagate_route_table_ids" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "要開啟 VGW route propagation 的 VPC route table，格式 `rtb-0123456789abcdef0`，不可重複。只用在 VGW 模式；transit gateway 的 propagation 設在 transit gateway 那邊。用 list 而不是 set：ID 在 plan 時可能還不知道。"

  validation {
    condition     = alltrue([for r in var.propagate_route_table_ids : can(regex("^rtb-[0-9a-f]{8,17}$", r))])
    error_message = "propagate_route_table_ids must look like rtb-0123456789abcdef0."
  }

  validation {
    condition     = length(distinct(var.propagate_route_table_ids)) == length(var.propagate_route_table_ids)
    error_message = "propagate_route_table_ids must not contain duplicates."
  }

  validation {
    condition     = length(var.propagate_route_table_ids) == 0 || var.vpn_gateway != null
    error_message = "propagate_route_table_ids only applies to a module-created virtual private gateway; configure propagation on the transit gateway instead."
  }
}

variable "tunnel_options" {
  type = object({
    phase1_encryption_algorithms = optional(list(string), ["AES256-GCM-16", "AES128-GCM-16", "AES256", "AES128"])
    phase1_integrity_algorithms  = optional(list(string), ["SHA2-256", "SHA2-384", "SHA2-512"])
    phase1_dh_group_numbers      = optional(list(number), [14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24])
    phase2_encryption_algorithms = optional(list(string), ["AES256-GCM-16", "AES128-GCM-16", "AES256", "AES128"])
    phase2_integrity_algorithms  = optional(list(string), ["SHA2-256", "SHA2-384", "SHA2-512"])
    phase2_dh_group_numbers      = optional(list(number), [14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24])
    phase1_lifetime_seconds      = optional(number, 28800)
    phase2_lifetime_seconds      = optional(number, 3600)
  })
  default     = {}
  nullable    = false
  description = "兩條 tunnel 共用的 IKE 參數，只收強參數：加密 `AES256-GCM-16`、`AES128-GCM-16`、`AES256`、`AES128`；完整性 `SHA2-256`、`SHA2-384`、`SHA2-512`（不收 `SHA1`）；Diffie-Hellman group 14–24（不收 2、5）；IKE 版本固定 `ikev2`。每個清單至少一個值。`phase1_lifetime_seconds` 900–28800，`phase2_lifetime_seconds` 900–3600 且要小於 phase 1。預設值是這些強參數的完整集合；地端設備只支援其中一部分時再縮小。"

  validation {
    condition = alltrue([
      for l in [var.tunnel_options.phase1_encryption_algorithms, var.tunnel_options.phase2_encryption_algorithms] :
      length(l) > 0 && alltrue([for a in l : contains(["AES256-GCM-16", "AES128-GCM-16", "AES256", "AES128"], a)])
    ])
    error_message = "tunnel_options encryption algorithms must be a non-empty list of AES256-GCM-16, AES128-GCM-16, AES256 or AES128."
  }

  validation {
    condition = alltrue([
      for l in [var.tunnel_options.phase1_integrity_algorithms, var.tunnel_options.phase2_integrity_algorithms] :
      length(l) > 0 && alltrue([for a in l : contains(["SHA2-256", "SHA2-384", "SHA2-512"], a)])
    ])
    error_message = "tunnel_options integrity algorithms must be a non-empty list of SHA2-256, SHA2-384 or SHA2-512; SHA1 is not accepted."
  }

  validation {
    condition = alltrue([
      for l in [var.tunnel_options.phase1_dh_group_numbers, var.tunnel_options.phase2_dh_group_numbers] :
      length(l) > 0 && alltrue([for g in l : contains([14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24], g)])
    ])
    error_message = "tunnel_options DH groups must be a non-empty list of groups 14-24; groups 2 and 5 are not accepted."
  }

  validation {
    condition = (
      var.tunnel_options.phase1_lifetime_seconds >= 900 && var.tunnel_options.phase1_lifetime_seconds <= 28800 &&
      var.tunnel_options.phase2_lifetime_seconds >= 900 && var.tunnel_options.phase2_lifetime_seconds <= 3600
    )
    error_message = "tunnel_options.phase1_lifetime_seconds must be 900-28800 and phase2_lifetime_seconds 900-3600."
  }

  validation {
    condition     = var.tunnel_options.phase2_lifetime_seconds < var.tunnel_options.phase1_lifetime_seconds
    error_message = "tunnel_options.phase2_lifetime_seconds must be less than phase1_lifetime_seconds."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 90
  nullable    = false
  description = "module 自己建的 tunnel log group 的保留天數，必須是 CloudWatch Logs 接受的值（預設 90）。"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, ... 3653)."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "各資源的 tag；`Name` 由 module 加上。"
}
