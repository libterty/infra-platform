variable "name" {
  type        = string
  description = "table 名稱，3–255 字元，限英數字、`_`、`-`、`.`。"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{3,255}$", var.name))
    error_message = "name must be 3-255 chars of letters, digits, underscores, hyphens or dots."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "table 加密（SSE）用的客戶管理 KMS key ARN，必填；不提供使用 AWS 擁有的 key 或 AWS 管理 key 的選項。key policy 要讓存取這張 table 的 role 能用這把 key。"

  validation {
    condition     = var.kms_key_arn != null && can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "hash_key" {
  type        = string
  description = "partition key 的屬性名稱，必須同時出現在 `attributes`。建立後不能改。"
}

variable "range_key" {
  type        = string
  default     = null
  description = "sort key 的屬性名稱；`null` 表示沒有 sort key。給了就必須同時出現在 `attributes`。建立後不能改。"
}

variable "attributes" {
  type        = map(string)
  description = "屬性名稱對應型別（`S`、`N`、`B`）。只能宣告用在 key 的屬性：`hash_key`、`range_key` 與 `global_secondary_indexes` 的 key，不缺也不多；TTL 屬性與其他資料欄位不要放進來。"

  validation {
    condition     = alltrue([for t in values(var.attributes) : contains(["S", "N", "B"], t)])
    error_message = "attributes types must be S, N or B."
  }

  validation {
    condition     = alltrue([for k in local.key_attribute_names : contains(keys(var.attributes), k)])
    error_message = "attributes must declare every attribute used as a key (hash_key, range_key and the keys of global_secondary_indexes)."
  }

  validation {
    condition     = alltrue([for a in keys(var.attributes) : contains(local.key_attribute_names, a)])
    error_message = "attributes must only declare attributes used as a key; remove the ones that are not hash_key, range_key or a global_secondary_indexes key."
  }
}

variable "billing_mode" {
  type        = string
  default     = "PAY_PER_REQUEST"
  nullable    = false
  description = "`PAY_PER_REQUEST`（預設，按請求計費）或 `PROVISIONED`（要給 `read_capacity`、`write_capacity`，GSI 也要各自給容量）。"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "read_capacity" {
  type        = number
  default     = null
  description = "table 的讀取容量單位，至少 1。`billing_mode = \"PROVISIONED\"` 時必填，`PAY_PER_REQUEST` 時必須是 `null`。"

  validation {
    condition     = var.billing_mode == "PROVISIONED" ? (var.read_capacity != null && try(var.read_capacity >= 1 && var.read_capacity == floor(var.read_capacity), false)) : var.read_capacity == null
    error_message = "read_capacity must be a whole number >= 1 when billing_mode is PROVISIONED, and must be null when it is PAY_PER_REQUEST."
  }
}

variable "write_capacity" {
  type        = number
  default     = null
  description = "table 的寫入容量單位，至少 1。`billing_mode = \"PROVISIONED\"` 時必填，`PAY_PER_REQUEST` 時必須是 `null`。"

  validation {
    condition     = var.billing_mode == "PROVISIONED" ? (var.write_capacity != null && try(var.write_capacity >= 1 && var.write_capacity == floor(var.write_capacity), false)) : var.write_capacity == null
    error_message = "write_capacity must be a whole number >= 1 when billing_mode is PROVISIONED, and must be null when it is PAY_PER_REQUEST."
  }
}

variable "global_secondary_indexes" {
  type = map(object({
    hash_key           = string
    range_key          = optional(string)
    projection_type    = optional(string, "ALL")
    non_key_attributes = optional(list(string))
    read_capacity      = optional(number)
    write_capacity     = optional(number)
  }))
  default     = {}
  nullable    = false
  description = "GSI，key 是 index 名稱（3–255 字元）。欄位：`hash_key`、`range_key`（都必須出現在 `attributes`，用 `key_schema` 寫入）、`projection_type`（`ALL`、`KEYS_ONLY`、`INCLUDE`，預設 `ALL`）、`non_key_attributes`（只有 `INCLUDE` 要給，而且必給）、`read_capacity`、`write_capacity`（`PROVISIONED` 時必填，`PAY_PER_REQUEST` 時必須是 `null`）。"

  validation {
    condition     = alltrue([for n in keys(var.global_secondary_indexes) : can(regex("^[a-zA-Z0-9_.-]{3,255}$", n))])
    error_message = "global_secondary_indexes names must be 3-255 chars of letters, digits, underscores, hyphens or dots."
  }

  validation {
    condition     = alltrue([for g in values(var.global_secondary_indexes) : contains(["ALL", "KEYS_ONLY", "INCLUDE"], g.projection_type)])
    error_message = "global_secondary_indexes projection_type must be ALL, KEYS_ONLY or INCLUDE."
  }

  validation {
    condition = alltrue([
      for g in values(var.global_secondary_indexes) :
      g.projection_type == "INCLUDE" ? length(coalesce(g.non_key_attributes, [])) > 0 : g.non_key_attributes == null
    ])
    error_message = "non_key_attributes is required (and must not be empty) with projection_type INCLUDE, and must not be set otherwise."
  }

  validation {
    condition = alltrue([
      for g in values(var.global_secondary_indexes) :
      var.billing_mode == "PROVISIONED" ? (
        g.read_capacity != null && g.write_capacity != null && try(g.read_capacity >= 1 && g.write_capacity >= 1, false)
      ) : (g.read_capacity == null && g.write_capacity == null)
    ])
    error_message = "Each GSI needs read_capacity and write_capacity (>= 1) when billing_mode is PROVISIONED, and must not set them when it is PAY_PER_REQUEST."
  }
}

variable "ttl_attribute" {
  type        = string
  default     = null
  description = "存放 TTL 過期時間（epoch 秒）的屬性名稱；`null` 不開 TTL。這個屬性不是 key，不要放進 `attributes`。"

  validation {
    condition     = var.ttl_attribute == null ? true : (length(var.ttl_attribute) >= 1 && length(var.ttl_attribute) <= 255)
    error_message = "ttl_attribute must be 1-255 chars; use null to disable TTL."
  }
}

variable "stream_view_type" {
  type        = string
  default     = null
  description = "`null` 不開 DynamoDB Streams；給值就開，並決定寫進 stream 的內容：`KEYS_ONLY`、`NEW_IMAGE`、`OLD_IMAGE`、`NEW_AND_OLD_IMAGES`。"

  validation {
    condition     = var.stream_view_type == null ? true : contains(["KEYS_ONLY", "NEW_IMAGE", "OLD_IMAGE", "NEW_AND_OLD_IMAGES"], var.stream_view_type)
    error_message = "stream_view_type must be KEYS_ONLY, NEW_IMAGE, OLD_IMAGE or NEW_AND_OLD_IMAGES."
  }
}

variable "point_in_time_recovery_days" {
  type        = number
  default     = 35
  nullable    = false
  description = "point-in-time recovery 的保留天數，1–35（預設 35）。PITR 固定開啟，沒有關閉的選項。"

  validation {
    condition     = var.point_in_time_recovery_days >= 1 && var.point_in_time_recovery_days <= 35 && var.point_in_time_recovery_days == floor(var.point_in_time_recovery_days)
    error_message = "point_in_time_recovery_days must be a whole number between 1 and 35."
  }
}

variable "deletion_protection" {
  type        = bool
  default     = true
  nullable    = false
  description = "刪除保護，預設開啟。要 destroy 之前，先把它設成 `false` 並 apply。"
}

variable "table_class" {
  type        = string
  default     = "STANDARD"
  nullable    = false
  description = "`STANDARD`（預設）或 `STANDARD_INFREQUENT_ACCESS`。"

  validation {
    condition     = contains(["STANDARD", "STANDARD_INFREQUENT_ACCESS"], var.table_class)
    error_message = "table_class must be STANDARD or STANDARD_INFREQUENT_ACCESS."
  }
}

variable "contributor_insights" {
  type        = bool
  default     = false
  nullable    = false
  description = "是否對 table 開 CloudWatch Contributor Insights（另外計費）。只開 table 本身，不含 GSI。"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "table 的 tag；`Name` 由 module 加上。"
}
