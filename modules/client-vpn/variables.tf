variable "name" {
  type        = string
  description = "Client VPN endpoint 的名稱，也是 `Name` tag 與 log group 名稱的一部分。2–63 字元，限小寫英數字與 `-`，以字母開頭。"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.name))
    error_message = "name must be lowercase letters, digits or hyphens, starting with a letter (2-63 characters)."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "module 自己建的 connection log group 加密用的客戶管理 KMS key ARN（symmetric），必填。key policy 要讓 CloudWatch Logs（`logs.<region>.amazonaws.com`）能使用這把 key。"

  validation {
    condition     = var.kms_key_arn != null && can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "server_certificate_arn" {
  type        = string
  description = "server 憑證在 ACM 的 ARN，不論用哪種驗證都必填。憑證要是 RSA 1024 或 2048 位元（AWS 文件）；module 只收 ARN，不收憑證或私鑰內容。"

  validation {
    condition     = var.server_certificate_arn != null && can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/[0-9a-f-]{36}$", var.server_certificate_arn))
    error_message = "server_certificate_arn must be an ACM certificate ARN (arn:<partition>:acm:<region>:<account>:certificate/<id>)."
  }
}

variable "authentication" {
  type = object({
    mutual_tls_root_certificate_arn = optional(string)
    saml_provider_arn               = optional(string)
    self_service_saml_provider_arn  = optional(string)
  })
  description = "驗證方式，至少要給一種，兩種都給就是兩者並用（連線要兩個都通過）。`mutual_tls_root_certificate_arn` 是簽發 client 憑證的 CA 在 ACM 的 ARN（client 憑證由同一個 CA 簽發時，可以填 server 憑證的 ARN）；`saml_provider_arn` 是 IAM SAML identity provider 的 ARN，要在 module 外建好（module 不建 IAM 資源）；`self_service_saml_provider_arn` 是自助入口用的 SAML provider ARN，給了就開啟自助入口，只能搭配 `saml_provider_arn`。不支援 Active Directory。"

  validation {
    condition     = var.authentication.mutual_tls_root_certificate_arn != null || var.authentication.saml_provider_arn != null
    error_message = "authentication needs at least one method: mutual_tls_root_certificate_arn or saml_provider_arn."
  }

  validation {
    condition     = var.authentication.self_service_saml_provider_arn == null || var.authentication.saml_provider_arn != null
    error_message = "authentication.self_service_saml_provider_arn needs saml_provider_arn; the self-service portal only works with SAML."
  }

  validation {
    condition     = var.authentication.mutual_tls_root_certificate_arn == null ? true : can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/[0-9a-f-]{36}$", var.authentication.mutual_tls_root_certificate_arn))
    error_message = "authentication.mutual_tls_root_certificate_arn must be an ACM certificate ARN; certificate bodies are not accepted."
  }

  validation {
    condition = alltrue([
      for a in [var.authentication.saml_provider_arn, var.authentication.self_service_saml_provider_arn] :
      a == null ? true : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:saml-provider/[A-Za-z0-9_+=,.@-]+$", a))
    ])
    error_message = "SAML provider ARNs must look like arn:aws:iam::<account>:saml-provider/<name>."
  }
}

variable "client_cidr_block" {
  type        = string
  description = "分配給 client 的 IPv4 網段，必須是網路位址，大小 `/12`–`/22`（AWS 建議 `/22`，要容納同時連線人數的兩倍），不可與 `vpc_cidr_blocks` 重疊；建立後不能改。也不可與日後手動加的 route 重疊，module 不檢查這一項。"

  validation {
    condition     = can(cidrnetmask(var.client_cidr_block)) ? cidrsubnet(var.client_cidr_block, 0, 0) == var.client_cidr_block : false
    error_message = "client_cidr_block must be an IPv4 network address such as 10.250.0.0/22."
  }

  validation {
    condition     = try(tonumber(split("/", var.client_cidr_block)[1]) >= 12 && tonumber(split("/", var.client_cidr_block)[1]) <= 22, false)
    error_message = "client_cidr_block must be between /12 and /22 in size."
  }

  # Two CIDRs overlap when they share the same network at the shorter of the two prefix lengths (Terraform has no cidroverlap function).
  # try() leaves malformed input to the checks above, so a bad CIDR does not add a second error here.
  validation {
    condition = alltrue([for v in var.vpc_cidr_blocks : try(
      [for m in [min(tonumber(split("/", var.client_cidr_block)[1]), tonumber(split("/", v)[1]))] :
        cidrsubnet("${cidrhost(var.client_cidr_block, 0)}/${m}", 0, 0) != cidrsubnet("${cidrhost(v, 0)}/${m}", 0, 0)
      ][0],
      true
    )])
    error_message = "client_cidr_block must not overlap any of vpc_cidr_blocks."
  }
}

variable "vpc_id" {
  type        = string
  description = "endpoint 所在的 VPC，格式 `vpc-0123456789abcdef0`；`subnet_ids` 與 `security_group_ids` 都要在這個 VPC 裡。"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must look like vpc-0123456789abcdef0."
  }
}

variable "vpc_cidr_blocks" {
  type        = list(string)
  description = "VPC 的所有 IPv4 網段（主要與次要），至少一個、必須是網路位址（例如 `10.30.0.0/20`）；用來擋下與 `client_cidr_block` 重疊的設定，AWS 不允許 client 網段與 VPC 重疊。"

  validation {
    condition     = length(var.vpc_cidr_blocks) > 0
    error_message = "Give at least one VPC CIDR block."
  }

  validation {
    condition     = alltrue([for c in var.vpc_cidr_blocks : can(cidrnetmask(c)) ? cidrsubnet(c, 0, 0) == c : false])
    error_message = "vpc_cidr_blocks must be IPv4 network addresses such as 10.30.0.0/20."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "要關聯的 subnet，至少一個、不可重複，格式 `subnet-0123456789abcdef0`，都要在 `vpc_id` 裡、且每個可用區最多一個（AWS 限制，module 無法在 plan 時檢查）。每個關聯另外計費。用 list 而不是 set：ID 在 plan 時可能還不知道。"

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "Give at least one subnet to associate."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))])
    error_message = "subnet_ids must look like subnet-0123456789abcdef0."
  }

  validation {
    condition     = length(distinct(var.subnet_ids)) == length(var.subnet_ids)
    error_message = "subnet_ids must not contain duplicates."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "套用在 endpoint 的 security group，至少一個、不可重複，格式 `sg-0123456789abcdef0`，由呼叫端建立（module 不建 security group）。必填，避免 AWS 在沒有指定時套用 VPC 的 default security group。"

  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "Give at least one security group; without one AWS applies the VPC default security group."
  }

  validation {
    condition     = alltrue([for s in var.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", s))])
    error_message = "security_group_ids must look like sg-0123456789abcdef0."
  }

  validation {
    condition     = length(distinct(var.security_group_ids)) == length(var.security_group_ids)
    error_message = "security_group_ids must not contain duplicates."
  }
}

variable "authorization_rules" {
  type = list(object({
    target_cidr     = string
    access_group_id = optional(string)
    description     = optional(string)
  }))
  default     = []
  nullable    = false
  description = "授權規則，AWS 預設拒絕，沒有規則就沒有人連得到任何網路。`target_cidr` 是開放的網段（網路位址格式）；`access_group_id` 是 SAML IdP 的群組，只在 `authentication.saml_provider_arn` 有給時能用，沒給就是對所有 client 開放。`0.0.0.0/0` 只在 `split_tunnel = false` 且 `allow_internet_access = true` 時才能用。同一組 `target_cidr` 與 `access_group_id` 不可重複。順序變動會讓規則重建，新規則請加在最後。"

  validation {
    condition     = alltrue([for r in var.authorization_rules : can(cidrnetmask(r.target_cidr)) ? cidrsubnet(r.target_cidr, 0, 0) == r.target_cidr : false])
    error_message = "authorization_rules target_cidr must be IPv4 network addresses such as 10.30.8.0/22."
  }

  validation {
    condition     = alltrue([for r in var.authorization_rules : r.target_cidr != "0.0.0.0/0" || (!var.split_tunnel && var.allow_internet_access)])
    error_message = "authorization_rules must not contain 0.0.0.0/0 unless split_tunnel = false and allow_internet_access = true."
  }

  validation {
    condition     = alltrue([for r in var.authorization_rules : r.access_group_id == null || var.authentication.saml_provider_arn != null])
    error_message = "access_group_id needs authentication.saml_provider_arn; groups come from the SAML identity provider."
  }

  validation {
    condition     = alltrue([for r in var.authorization_rules : r.access_group_id == null ? true : length(r.access_group_id) > 0])
    error_message = "access_group_id must not be an empty string; use null to authorize all groups."
  }

  validation {
    condition     = length(distinct([for r in var.authorization_rules : "${r.target_cidr}|${r.access_group_id == null ? "" : r.access_group_id}"])) == length(var.authorization_rules)
    error_message = "authorization_rules must not contain the same target_cidr and access_group_id twice."
  }
}

variable "routes" {
  type = list(object({
    destination_cidr = string
    target_subnet_id = string
    description      = optional(string)
  }))
  default     = []
  nullable    = false
  description = "endpoint route table 的額外路由（VPC 本身的路由由 AWS 在第一次關聯 subnet 時自動加）。`destination_cidr` 是目的網段（網路位址格式）；`target_subnet_id` 是要送出的已關聯 subnet，必須在 `subnet_ids` 裡。`0.0.0.0/0` 只在 `split_tunnel = false` 且 `allow_internet_access = true` 時才能用。目的網段不可重複。順序變動會讓路由重建，新路由請加在最後。"

  validation {
    condition     = alltrue([for r in var.routes : can(cidrnetmask(r.destination_cidr)) ? cidrsubnet(r.destination_cidr, 0, 0) == r.destination_cidr : false])
    error_message = "routes destination_cidr must be IPv4 network addresses such as 192.168.10.0/24."
  }

  validation {
    condition     = alltrue([for r in var.routes : r.destination_cidr != "0.0.0.0/0" || (!var.split_tunnel && var.allow_internet_access)])
    error_message = "routes must not contain 0.0.0.0/0 unless split_tunnel = false and allow_internet_access = true."
  }

  validation {
    condition     = alltrue([for r in var.routes : contains(var.subnet_ids, r.target_subnet_id)])
    error_message = "routes target_subnet_id must be one of subnet_ids; a route can only target an associated subnet."
  }

  validation {
    condition     = length(distinct([for r in var.routes : r.destination_cidr])) == length(var.routes)
    error_message = "routes must not contain the same destination_cidr twice."
  }
}

variable "split_tunnel" {
  type        = bool
  default     = true
  nullable    = false
  description = "是否啟用 split tunnel（預設 `true`）：只有目的地在 endpoint route table 裡的流量走 VPN，client 其他流量走自己的網路。`false` 是 full tunnel，所有流量都走 VPN，這時要讓 client 上網才需要 `0.0.0.0/0`，並同時設 `allow_internet_access = true`。"
}

variable "allow_internet_access" {
  type        = bool
  default     = false
  nullable    = false
  description = "明確允許 `0.0.0.0/0` 出現在授權規則與路由（預設 `false`）。只能在 `split_tunnel = false` 時設為 `true`；AWS 文件指出 split tunnel 加 `0.0.0.0/0` 路由可能造成連線中斷，不建議。"

  validation {
    condition     = !var.allow_internet_access || !var.split_tunnel
    error_message = "allow_internet_access = true needs split_tunnel = false; a default route with split tunnel can disrupt client connectivity."
  }
}

variable "session_timeout_hours" {
  type        = number
  default     = 12
  nullable    = false
  description = "最長連線時數，到時 client 要重新驗證，只能是 8、10、12、24（預設 12；provider 與 AWS 的預設是 24）。"

  validation {
    condition     = contains([8, 10, 12, 24], var.session_timeout_hours)
    error_message = "session_timeout_hours must be 8, 10, 12 or 24."
  }
}

variable "dns_servers" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "client 使用的 DNS server（IPv4），最多兩個；空的就用 client 自己裝置的 DNS。full tunnel 時 Windows 會強制 DNS 走 VPN，要有一個 VPN 內連得到的 DNS server。"

  validation {
    condition     = length(var.dns_servers) <= 2
    error_message = "dns_servers may hold at most two addresses."
  }

  validation {
    condition     = alltrue([for d in var.dns_servers : can(regex("^((25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])$", d))])
    error_message = "dns_servers must be IPv4 addresses such as 10.30.0.2."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 90
  nullable    = false
  description = "module 自己建的 connection log group 的保留天數，必須是 CloudWatch Logs 接受的值（預設 90）。"

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
