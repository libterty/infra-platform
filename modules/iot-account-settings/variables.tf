variable "indexing" {
  type = object({
    thing_indexing_mode              = string
    thing_connectivity_indexing_mode = optional(string, "OFF")
    named_shadow_indexing_mode       = optional(string, "OFF")
    device_defender_indexing_mode    = optional(string, "OFF")
    thing_group_indexing_mode        = optional(string, "OFF")
    custom_fields                    = optional(map(string), {})
  })
  default     = null
  description = "fleet indexing 設定；`null` 就不建。`thing_indexing_mode` 為 `OFF`、`REGISTRY`、`REGISTRY_AND_SHADOW`；`thing_connectivity_indexing_mode` 為 `OFF`、`STATUS`；`named_shadow_indexing_mode`、`thing_group_indexing_mode` 為 `OFF`、`ON`；`device_defender_indexing_mode` 為 `OFF`、`VIOLATIONS`（要搭 `thing_indexing_mode` 不是 `OFF`）；沒給的都是 `OFF`。`custom_fields` 是欄位名稱（例如 `attributes.model`）→ 型別（`Number`、`String`、`Boolean`）。**每個帳號、每個 region 只能由一處呼叫。**"

  validation {
    condition     = var.indexing == null || contains(["OFF", "REGISTRY", "REGISTRY_AND_SHADOW"], var.indexing.thing_indexing_mode)
    error_message = "indexing.thing_indexing_mode must be OFF, REGISTRY or REGISTRY_AND_SHADOW."
  }

  validation {
    condition     = var.indexing == null || contains(["OFF", "STATUS"], var.indexing.thing_connectivity_indexing_mode)
    error_message = "indexing.thing_connectivity_indexing_mode must be OFF or STATUS."
  }

  validation {
    condition     = var.indexing == null || contains(["OFF", "ON"], var.indexing.named_shadow_indexing_mode)
    error_message = "indexing.named_shadow_indexing_mode must be OFF or ON."
  }

  validation {
    condition     = var.indexing == null || contains(["OFF", "VIOLATIONS"], var.indexing.device_defender_indexing_mode)
    error_message = "indexing.device_defender_indexing_mode must be OFF or VIOLATIONS."
  }

  validation {
    condition     = var.indexing == null || contains(["OFF", "ON"], var.indexing.thing_group_indexing_mode)
    error_message = "indexing.thing_group_indexing_mode must be OFF or ON."
  }

  validation {
    condition     = var.indexing == null || alltrue([for t in values(var.indexing.custom_fields) : contains(["Number", "String", "Boolean"], t)])
    error_message = "indexing.custom_fields values must be Number, String or Boolean."
  }

  # Device Defender violations are indexed on things, so the thing index has to exist.
  validation {
    condition     = var.indexing == null || var.indexing.device_defender_indexing_mode != "VIOLATIONS" || var.indexing.thing_indexing_mode != "OFF"
    error_message = "indexing.device_defender_indexing_mode VIOLATIONS requires thing_indexing_mode REGISTRY or REGISTRY_AND_SHADOW."
  }
}

variable "logging" {
  type = object({
    role_arn          = string
    default_log_level = optional(string, "WARN")
  })
  default     = null
  description = "IoT Core 的帳號層 logging（`SetV2LoggingOptions`，作用在整個 fleet）；`null` 就不建。`role_arn` 是讓 IoT 寫 CloudWatch Logs 的 role，由呼叫端建立；`default_log_level` 為 `DEBUG`、`INFO`、`WARN`、`ERROR`、`DISABLED`（預設 `WARN`）。**每個帳號、每個 region 只能由一處呼叫。**"

  validation {
    condition     = var.logging == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[a-zA-Z0-9_+=,.@/-]+$", var.logging.role_arn))
    error_message = "logging.role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }

  validation {
    condition     = var.logging == null || contains(["DEBUG", "INFO", "WARN", "ERROR", "DISABLED"], var.logging.default_log_level)
    error_message = "logging.default_log_level must be DEBUG, INFO, WARN, ERROR or DISABLED."
  }
}

variable "event_configurations" {
  type        = map(bool)
  default     = null
  description = "registry 事件的開關，事件種類（`THING`、`THING_GROUP`、`THING_TYPE`、`THING_GROUP_MEMBERSHIP`、`THING_GROUP_HIERARCHY`、`THING_TYPE_ASSOCIATION`、`JOB`、`JOB_EXECUTION`、`POLICY`、`CERTIFICATE`、`CA_CERTIFICATE`）→ 是否發布；`null` 就不建。從設定移除不會關掉事件，要關就設成 `false`。**每個帳號、每個 region 只能由一處呼叫。**"

  validation {
    condition = var.event_configurations == null || alltrue([for k in keys(var.event_configurations) : contains([
      "THING", "THING_GROUP", "THING_TYPE", "THING_GROUP_MEMBERSHIP", "THING_GROUP_HIERARCHY", "THING_TYPE_ASSOCIATION",
      "JOB", "JOB_EXECUTION", "POLICY", "CERTIFICATE", "CA_CERTIFICATE",
    ], k)])
    error_message = "event_configurations keys must be THING, THING_GROUP, THING_TYPE, THING_GROUP_MEMBERSHIP, THING_GROUP_HIERARCHY, THING_TYPE_ASSOCIATION, JOB, JOB_EXECUTION, POLICY, CERTIFICATE or CA_CERTIFICATE."
  }
}
