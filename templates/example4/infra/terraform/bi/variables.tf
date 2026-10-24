variable "redshift_reader_secret_arn" {
  description = "QuickSight 連 Redshift 用的 Secrets Manager secret ARN，選填。`null`（dev、sit 預設）只建 Athena 資料來源。secret 在 repo 外建立，內容是專用唯讀 DB user 的 `username`、`password`（設計 D10）；給了就建 Redshift 資料來源與 VPC connection。QuickSight 管理者要在主控台把這個 secret 授權給 QuickSight，執行 Terraform 的身分要有它的 `secretsmanager:GetSecretValue`。"
  type        = string
  default     = null

  validation {
    condition     = var.redshift_reader_secret_arn == null ? true : can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:.+$", var.redshift_reader_secret_arn))
    error_message = "redshift_reader_secret_arn must be null or a Secrets Manager secret ARN (arn:<partition>:secretsmanager:<region>:<account>:secret:<name>)."
  }
}

variable "owner_principals" {
  description = "擁有者的 QuickSight user 或 group ARN（`arn:aws:quicksight:<identity region>:<account>:group/<namespace>/<name>`），對所有 data source 與 dataset 有修改與改權限的 action。QuickSight 帳號、user、group 在 Terraform 之外管理。不能同時出現在 `reader_principals`。"
  type        = list(string)
  default     = []
}

variable "reader_principals" {
  description = "唯讀使用者的 QuickSight user 或 group ARN，格式同 `owner_principals`，只能檢視與使用 data source、dataset。"
  type        = list(string)
  default     = []
}

variable "datasets" {
  description = "QuickSight dataset，key 是 dataset 的 ID 與名稱。`source` 是 `athena`（預設，讀 curated database，`schema` 沒給就用 curated database）或 `redshift`（要有 `redshift_reader_secret_arn`；`schema` 是 Redshift 的 schema，沒給用 `public`）；`table` 是來源上的表名（curated 的表由 Glue job 建立，名稱與欄位要跟它的輸出一致）；`columns` 的 `type` 是 `STRING`、`INTEGER`、`DECIMAL`、`DATETIME`、`BIT`、`BOOLEAN`、`JSON`、`SEMISTRUCT`。一律 `DIRECT_QUERY`。"
  type = map(object({
    source = optional(string, "athena")
    schema = optional(string)
    table  = string
    columns = list(object({
      name = string
      type = string
    }))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for _, d in var.datasets : contains(["athena", "redshift"], d.source)])
    error_message = "A dataset source must be athena or redshift."
  }

  validation {
    condition     = alltrue([for _, d in var.datasets : d.source != "redshift"]) || var.redshift_reader_secret_arn != null
    error_message = "A redshift dataset needs redshift_reader_secret_arn: without it no Redshift data source is built."
  }
}
