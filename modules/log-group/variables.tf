variable "name" {
  type        = string
  description = "log group 名稱，1–512 字元，限英數字與 `_`、`.`、`/`、`#`、`-`，不可以 `aws/` 開頭。"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.name)) && !startswith(var.name, "aws/")
    error_message = "name must be 1-512 chars of letters, digits, _ . / # or -, and must not start with aws/."
  }
}

variable "retention_days" {
  type        = number
  default     = 30
  description = "保留天數，只接受 CloudWatch Logs 允許的值：`1`、`3`、`5`、`7`、`14`、`30`、`60`、`90`、`120`、`150`、`180`、`365`、`400`、`545`、`731`、`1096`、`1827`、`2192`、`2557`、`2922`、`3288`、`3653`。不接受 `0`（永不過期）。"
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.retention_days)
    error_message = "retention_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, ... 3653)."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "自管 KMS key 的 ARN，`null` 時用 CloudWatch Logs 預設加密。key policy 要允許 `logs.<region>.amazonaws.com`。"
}

variable "subscription" {
  type = object({
    destination_arn = string
    filter_pattern  = optional(string, "")
    role_arn        = optional(string)
  })
  default     = null
  description = "選用的 subscription filter，`null` 時不建。欄位：`destination_arn`（必填，Lambda、Kinesis、Firehose 或 logs destination 的 ARN）、`filter_pattern`（預設 `\"\"`，空字串時轉送所有事件）、`role_arn`（目的地是 Kinesis、Firehose 時必填）。"
  validation {
    condition = var.subscription == null ? true : (
      can(regex("^arn:aws[a-z-]*:(lambda|kinesis|firehose|logs):", var.subscription.destination_arn)) &&
      (can(regex(":(kinesis|firehose):", var.subscription.destination_arn)) ? var.subscription.role_arn != null : true)
    )
    error_message = "destination_arn must be a Lambda, Kinesis, Firehose or logs destination ARN; Kinesis and Firehose need role_arn."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "log group 的 tag；`Name` 由 module 加上。"
}
