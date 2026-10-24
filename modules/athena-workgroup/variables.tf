variable "name" {
  type        = string
  description = "workgroup 名稱，1–128 字元，限英數字、`_`、`-`、`.`。"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,128}$", var.name))
    error_message = "name must be 1-128 chars of letters, digits, underscores, hyphens or dots."
  }
}

variable "results_bucket_name" {
  type        = string
  description = "存放查詢結果的 S3 bucket 名稱（只有名稱，不含 `s3://`）。bucket 由呼叫端建立，查詢者的 role 要有它的讀寫權限。"

  validation {
    condition     = var.results_bucket_name != null && can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.results_bucket_name))
    error_message = "results_bucket_name must be an S3 bucket name (3-63 chars of lowercase letters, digits, dots and hyphens), not an s3:// URL or ARN."
  }
}

variable "results_prefix" {
  type        = string
  default     = "athena-results/"
  nullable    = false
  description = "查詢結果在 bucket 裡的前綴；空字串代表 bucket 根目錄，否則要以 `/` 結尾且不以 `/` 開頭（預設 `athena-results/`）。"

  validation {
    condition     = can(regex("^([A-Za-z0-9!_.*'()=-]+/)*$", var.results_prefix))
    error_message = "results_prefix must be empty or slash-terminated path segments (for example athena-results/), without a leading slash or an s3:// scheme."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "查詢結果加密用的客戶管理 KMS key ARN（symmetric），必填。結果一律用 `SSE_KMS`；查詢者的 role 要有這把 key 的 `kms:GenerateDataKey` 與 `kms:Decrypt`。"

  validation {
    condition     = var.kms_key_arn != null && can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "bytes_scanned_cutoff_per_query" {
  type        = number
  default     = 10737418240
  nullable    = false
  description = "單一查詢最多可掃描的位元組數，超過就取消查詢；至少 `10485760`（10 MiB，provider 的下限；AWS API 文件寫 `10000000`），預設 10 GiB（`10737418240`）。不提供「不設上限」的選項。"

  validation {
    condition     = var.bytes_scanned_cutoff_per_query >= 10485760 && var.bytes_scanned_cutoff_per_query == floor(var.bytes_scanned_cutoff_per_query)
    error_message = "bytes_scanned_cutoff_per_query must be a whole number of bytes, at least 10485760 (the provider minimum; the AWS API documents 10000000)."
  }
}

variable "engine_version" {
  type        = string
  default     = "AUTO"
  nullable    = false
  description = "Athena SQL 引擎版本：`AUTO`（預設，由 AWS 選）或指定的 `Athena engine version N`（例如 `Athena engine version 3`）。"

  validation {
    condition     = var.engine_version == "AUTO" || can(regex("^Athena engine version [0-9]+$", var.engine_version))
    error_message = "engine_version must be AUTO or 'Athena engine version <N>' (for example 'Athena engine version 3')."
  }
}

variable "named_queries" {
  type = map(object({
    database    = string
    query       = string
    description = optional(string)
  }))
  default     = {}
  nullable    = false
  description = "要建在 workgroup 裡的 named query，key 是名稱；`database` 是 Glue database 名稱，`query` 是 SQL（不可為空）。"

  validation {
    condition     = alltrue([for q in values(var.named_queries) : trimspace(q.query) != "" && trimspace(q.database) != ""])
    error_message = "Each named query needs a non-empty database and query."
  }
}

variable "force_destroy" {
  type        = bool
  default     = false
  nullable    = false
  description = "刪除 workgroup 時是否連同其中的 named query 與查詢歷史一起刪除（預設 `false`）。"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "workgroup 的 tag；`Name` 由 module 加上。"
}
