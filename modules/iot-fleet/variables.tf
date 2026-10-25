variable "thing_types" {
  type = map(object({
    description           = optional(string)
    searchable_attributes = optional(set(string), [])
  }))
  default     = {}
  nullable    = false
  description = "thing type，名稱（1–128 字元，限英數字、`:`、`_`、`-`）→ 設定。`searchable_attributes` 最多 3 個。"

  validation {
    condition     = alltrue([for name in keys(var.thing_types) : can(regex("^[a-zA-Z0-9:_-]{1,128}$", name))])
    error_message = "thing_types keys must be 1-128 chars of letters, digits, colons, underscores or hyphens."
  }

  validation {
    condition     = alltrue([for t in values(var.thing_types) : length(t.searchable_attributes) <= 3])
    error_message = "thing_types[*].searchable_attributes may hold at most 3 attributes."
  }
}

variable "thing_groups" {
  type = map(object({
    parent      = optional(string)
    description = optional(string)
    attributes  = optional(map(string), {})
  }))
  default     = {}
  nullable    = false
  description = "thing group，名稱（1–128 字元，限英數字、`:`、`_`、`-`）→ 設定。`parent` 是同一個 map 裡另一個群組的名稱，`null` 就是最上層；階層最多 4 層、不能成環。"

  validation {
    condition     = alltrue([for name in keys(var.thing_groups) : can(regex("^[a-zA-Z0-9:_-]{1,128}$", name))])
    error_message = "thing_groups keys must be 1-128 chars of letters, digits, colons, underscores or hyphens."
  }

  validation {
    condition     = alltrue([for name, g in var.thing_groups : g.parent == null || (g.parent != name && contains(keys(var.thing_groups), coalesce(g.parent, "-")))])
    error_message = "thing_groups[*].parent must be the name of another group in thing_groups."
  }

  # The fourth ancestor of every group must be null: a group deeper than the four levels the module creates, or
  # one in a cycle, always has one. The nested single-item for expressions only bind each ancestor to a name.
  validation {
    condition = alltrue([for name, g in var.thing_groups : alltrue([
      for a1 in [g.parent] : alltrue([
        for a2 in [a1 == null ? null : try(var.thing_groups[a1].parent, null)] : alltrue([
          for a3 in [a2 == null ? null : try(var.thing_groups[a2].parent, null)] : alltrue([
            for a4 in [a3 == null ? null : try(var.thing_groups[a3].parent, null)] : a4 == null
          ])
        ])
      ])
    ])])
    error_message = "thing_groups must form a hierarchy of at most 4 levels without cycles."
  }
}

variable "policies" {
  type        = any
  default     = {}
  nullable    = false
  description = "IoT policy，名稱（1–128 字元，限英數字與 `_+=,.@-`）→ policy 文件物件（`Version`、`Statement`），module 用 `jsonencode` 轉成 JSON。每個 statement 都要有 `Effect`、`Action`、`Resource`；不准 `Allow` 的 `Action` 含 `iot:*` 或 `*` 又搭 `Resource` `*`。裝置 policy 建議用 `$${iot:Connection.Thing.ThingName}` 限縮到自己的 client id 與 topic。"

  validation {
    condition     = can([for name, doc in var.policies : regex("^[a-zA-Z0-9_+=,.@-]{1,128}$", name)])
    error_message = "policies keys must be 1-128 chars of letters, digits or _+=,.@- characters."
  }

  validation {
    condition = try(alltrue(flatten([for name, doc in var.policies : [
      length(doc.Statement) > 0,
      [for s in doc.Statement : contains(["Allow", "Deny"], s.Effect) && length(flatten([s.Action])) > 0 && length(flatten([s.Resource])) > 0],
    ]])), false)
    error_message = "policies values must be policy documents with a non-empty Statement list; every statement needs Effect (Allow or Deny), Action and Resource."
  }

  validation {
    condition = try(alltrue(flatten([for name, doc in var.policies : [for s in doc.Statement :
      !(s.Effect == "Allow" && length(setintersection(toset(flatten([s.Action])), ["iot:*", "*"])) > 0 && contains(flatten([s.Resource]), "*"))
    ]])), false)
    error_message = "policies must not allow iot:* or * actions on Resource *."
  }
}

variable "role_alias" {
  type = object({
    alias               = string
    role_arn            = string
    credential_duration = optional(number, 3600)
  })
  default     = null
  description = "IoT role alias（例如 Greengrass token exchange service 用的）；`null` 就不建。`role_arn` 由呼叫端建立，trust 要是 `credentials.iot.amazonaws.com`；`credential_duration` 單位秒，900–43200（預設 3600）。"

  validation {
    condition     = var.role_alias == null || can(regex("^[a-zA-Z0-9=,@-]{1,128}$", var.role_alias.alias))
    error_message = "role_alias.alias must be 1-128 chars of letters, digits or =,@- characters."
  }

  validation {
    condition     = var.role_alias == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[a-zA-Z0-9_+=,.@/-]+$", var.role_alias.role_arn))
    error_message = "role_alias.role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }

  validation {
    condition     = var.role_alias == null || try(var.role_alias.credential_duration >= 900 && var.role_alias.credential_duration <= 43200 && var.role_alias.credential_duration == floor(var.role_alias.credential_duration), false)
    error_message = "role_alias.credential_duration must be a whole number of seconds between 900 and 43200."
  }
}

variable "provisioning_template" {
  type = object({
    name                  = string
    description           = optional(string)
    template_body         = any
    provisioning_role_arn = string
    enabled               = bool
    pre_provisioning_hook = optional(object({
      target_arn      = string
      payload_version = optional(string, "2020-04-01")
    }))
  })
  default     = null
  description = "fleet provisioning（by claim）的 template；`null` 就不建。`name` 1–36 字元，限英數字、`_`、`-`；`template_body` 是 template 物件（`Parameters`、`Resources`），module 用 `jsonencode` 轉成 JSON；`provisioning_role_arn` 由呼叫端建立，trust 要是 `iot.amazonaws.com`；`enabled` 必填。`pre_provisioning_hook.target_arn` 是 Lambda ARN，`null` 就不掛 hook（取捨見 README〈注意〉）。"

  validation {
    condition     = var.provisioning_template == null || can(regex("^[0-9A-Za-z_-]{1,36}$", var.provisioning_template.name))
    error_message = "provisioning_template.name must be 1-36 chars of letters, digits, underscores or hyphens."
  }

  validation {
    condition     = var.provisioning_template == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[a-zA-Z0-9_+=,.@/-]+$", var.provisioning_template.provisioning_role_arn))
    error_message = "provisioning_template.provisioning_role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }

  validation {
    condition     = var.provisioning_template == null || try(var.provisioning_template.pre_provisioning_hook == null || can(regex("^arn:aws[a-z-]*:lambda:[a-z0-9-]+:[0-9]{12}:function:[a-zA-Z0-9_-]{1,64}(:[a-zA-Z0-9_$-]+)?$", var.provisioning_template.pre_provisioning_hook.target_arn)), false)
    error_message = "provisioning_template.pre_provisioning_hook.target_arn must be a Lambda function ARN (arn:<partition>:lambda:<region>:<account>:function:<name>[:<qualifier>])."
  }
}

variable "ca_certificate" {
  type = object({
    pem                     = string
    mode                    = optional(string, "SNI_ONLY")
    active                  = optional(bool, true)
    allow_auto_registration = optional(bool, false)
    registration_template = optional(object({
      template_body = any
      role_arn      = string
    }))
  })
  default     = null
  description = "要註冊到 IoT Core 的 CA 憑證（例如 `acm-pca` 簽的）；`null` 就不註冊。`pem` 是 PEM 格式的 CA 憑證（不含私鑰）；`mode` 只能 `SNI_ONLY`（`DEFAULT` 要 verification certificate，module 不收）；`active` 預設 `true`；`allow_auto_registration` 預設 `false`；`registration_template` 是 JITP 用的 template 物件與 role。"

  validation {
    condition     = var.ca_certificate == null || try(var.ca_certificate.mode == "SNI_ONLY", false)
    error_message = "ca_certificate.mode must be SNI_ONLY; DEFAULT needs a verification certificate, which this module does not take."
  }

  validation {
    condition     = var.ca_certificate == null || can(regex("-----BEGIN CERTIFICATE-----", var.ca_certificate.pem))
    error_message = "ca_certificate.pem must be a PEM-encoded certificate."
  }

  validation {
    condition     = var.ca_certificate == null || try(var.ca_certificate.registration_template == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[a-zA-Z0-9_+=,.@/-]+$", var.ca_certificate.registration_template.role_arn)), false)
    error_message = "ca_certificate.registration_template.role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "資源的 tag；`Name` 由 module 加上（CA 憑證沒有名稱，不加）。"
}
