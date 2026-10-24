variable "aws_account_id" {
  type        = string
  description = "QuickSight 資源所在的 AWS 帳號 ID（12 位數字）。QuickSight 的 data source、dataset、VPC connection 都以帳號與 region 為範圍，ID 在同一個帳號與 region 內必須唯一。"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account id."
  }
}

variable "athena_sources" {
  type = map(object({
    workgroup = string
    role_arn  = string
  }))
  default     = {}
  nullable    = false
  description = "Athena data source，key 同時是 data source 的 ID 與名稱（1–128 字元，限英數字、`_`、`-`）。`workgroup` 是查詢用的 Athena workgroup；`role_arn` 是這個 data source 專用的 IAM role ARN（覆蓋帳號層預設 role，module 不建 role）。role 的信任對象是 `quicksight.amazonaws.com`，權限限於這個 workgroup 的查詢、資料來源 bucket 與查詢結果 bucket 的讀寫、Glue catalog 讀取與用到的 KMS key。"

  validation {
    condition     = alltrue([for k, _ in var.athena_sources : can(regex("^[a-zA-Z0-9_-]{1,128}$", k))])
    error_message = "athena_sources keys must be 1-128 chars of letters, digits, underscores or hyphens (they become the QuickSight data source ids)."
  }

  validation {
    condition     = alltrue([for _, s in var.athena_sources : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", s.role_arn))])
    error_message = "athena_sources role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }

  validation {
    condition     = alltrue([for _, s in var.athena_sources : s.workgroup != null && length(s.workgroup) >= 1 && length(s.workgroup) <= 128])
    error_message = "athena_sources workgroup must be 1-128 chars."
  }
}

variable "redshift_sources" {
  type = map(object({
    host       = string
    port       = optional(number, 5439)
    database   = string
    secret_arn = string
  }))
  default     = {}
  nullable    = false
  description = "Redshift data source，key 同時是 data source 的 ID 與名稱（1–128 字元，限英數字、`_`、`-`，不可跟 `athena_sources` 的 key 重複）；空 map 就一個都不建。`host`、`port`（預設 5439）、`database` 是連線目標；`secret_arn` 是 Secrets Manager secret 的 ARN，secret 要有 `username`、`password`，用專用的唯讀 DB user，secret 在 repo 外建立。Redshift 來源只支援 secret，module 沒有帳密輸入。要先在 QuickSight 主控台把這個 secret 授權給 QuickSight，且執行 Terraform 的身分要有這個 secret 的 `secretsmanager:GetSecretValue`。有任何 Redshift 來源就必須給 `vpc_connection`。連線一律開 SSL。"

  validation {
    condition     = alltrue([for k, _ in var.redshift_sources : can(regex("^[a-zA-Z0-9_-]{1,128}$", k))])
    error_message = "redshift_sources keys must be 1-128 chars of letters, digits, underscores or hyphens (they become the QuickSight data source ids)."
  }

  validation {
    condition     = length(setintersection(keys(var.redshift_sources), keys(var.athena_sources))) == 0
    error_message = "redshift_sources keys must not repeat athena_sources keys (data source ids are unique per account and region)."
  }

  validation {
    condition     = alltrue([for _, s in var.redshift_sources : s.host != null && length(s.host) >= 1 && length(s.host) <= 256 && s.database != null && length(s.database) >= 1 && length(s.database) <= 128])
    error_message = "redshift_sources host must be 1-256 chars and database 1-128 chars."
  }

  validation {
    condition     = alltrue([for _, s in var.redshift_sources : s.port >= 1 && s.port <= 65535 && s.port == floor(s.port)])
    error_message = "redshift_sources port must be a whole number between 1 and 65535."
  }

  validation {
    condition     = alltrue([for _, s in var.redshift_sources : can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:.+$", s.secret_arn))])
    error_message = "redshift_sources secret_arn must be a Secrets Manager secret ARN (arn:<partition>:secretsmanager:<region>:<account>:secret:<name>); credentials are never given as plain inputs."
  }

  validation {
    condition     = length(var.redshift_sources) == 0 || var.vpc_connection != null
    error_message = "redshift_sources needs vpc_connection: Redshift sits in private subnets and QuickSight can only reach it through a VPC connection."
  }
}

variable "vpc_connection" {
  type = object({
    name               = string
    role_arn           = string
    subnet_ids         = list(string)
    security_group_ids = list(string)
    dns_resolvers      = optional(list(string), [])
  })
  default     = null
  description = "QuickSight 連進 VPC 的 VPC connection；`null` 不建（只有 Athena 來源時用）。`name` 同時是 connection 的 ID 與名稱（1–128 字元，限英數字、`_`、`-`）；`role_arn` 是 QuickSight 建 ENI 用的 IAM role ARN（module 不建 role，信任 `quicksight.amazonaws.com`，需要 `ec2:CreateNetworkInterface`、`ec2:ModifyNetworkInterfaceAttribute`、`ec2:DeleteNetworkInterface`、`ec2:DescribeSubnets`、`ec2:DescribeSecurityGroups`）；`subnet_ids` 2–15 個（provider 不接受單一 subnet；建議放在不同 AZ，module 驗不了），`security_group_ids` 1–16 個（security group 由呼叫端建，要能連到 Redshift 的 port）；`dns_resolvers` 選填，自有 DNS 才需要。VPC connection 需要 QuickSight Enterprise 版。"

  validation {
    condition     = var.vpc_connection == null ? true : can(regex("^[a-zA-Z0-9_-]{1,128}$", var.vpc_connection.name))
    error_message = "vpc_connection name must be 1-128 chars of letters, digits, underscores or hyphens."
  }

  validation {
    condition     = var.vpc_connection == null ? true : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.vpc_connection.role_arn))
    error_message = "vpc_connection role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }

  validation {
    condition     = var.vpc_connection == null ? true : length(var.vpc_connection.subnet_ids) >= 2 && length(var.vpc_connection.subnet_ids) <= 15 && alltrue([for s in var.vpc_connection.subnet_ids : can(regex("^subnet-[0-9a-z]+$", s))])
    error_message = "vpc_connection subnet_ids needs 2-15 subnet ids (subnet-...); the provider rejects a single subnet."
  }

  validation {
    condition     = var.vpc_connection == null ? true : length(var.vpc_connection.security_group_ids) >= 1 && length(var.vpc_connection.security_group_ids) <= 16 && alltrue([for s in var.vpc_connection.security_group_ids : can(regex("^sg-[0-9a-z]+$", s))])
    error_message = "vpc_connection security_group_ids needs 1-16 security group ids (sg-...)."
  }
}

variable "datasets" {
  type = map(object({
    source_key  = string
    import_mode = optional(string, "DIRECT_QUERY")
    sql         = optional(string)
    table = optional(object({
      name    = string
      schema  = optional(string)
      catalog = optional(string)
    }))
    columns = list(object({
      name = string
      type = string
    }))
  }))
  default     = {}
  nullable    = false
  description = "dataset，key 同時是 dataset 的 ID、名稱與 logical table 別名（1–128 字元，限英數字、`_`、`-`）。`source_key` 是 `athena_sources` 或 `redshift_sources` 的 key；資料來源用 `sql`（自訂 SQL）或 `table`（`name`、`schema`、`catalog` 指到來源上的表，Athena 的 `catalog` 是 `AwsDataCatalog`、`schema` 是 Glue database），兩者恰好給一個；`columns` 至少一個，`type` 是 `STRING`、`INTEGER`、`DECIMAL`、`DATETIME`、`BIT`、`BOOLEAN`、`JSON`、`SEMISTRUCT`，要跟查詢結果的欄位一致；`import_mode` 是 `DIRECT_QUERY`（預設，每次查詢都打來源）或 `SPICE`（要帳號有 SPICE 容量，module 不排程重新整理）。"

  validation {
    condition     = alltrue([for k, _ in var.datasets : can(regex("^[a-zA-Z0-9_-]{1,128}$", k))])
    error_message = "datasets keys must be 1-128 chars of letters, digits, underscores or hyphens (they become the QuickSight dataset ids)."
  }

  validation {
    condition     = alltrue([for _, d in var.datasets : contains(setunion(keys(var.athena_sources), keys(var.redshift_sources)), d.source_key)])
    error_message = "datasets source_key must be a key of athena_sources or redshift_sources."
  }

  validation {
    condition     = alltrue([for _, d in var.datasets : (d.sql != null) != (d.table != null)])
    error_message = "Each dataset needs exactly one of sql and table."
  }

  validation {
    condition     = alltrue([for _, d in var.datasets : d.sql == null ? true : trimspace(d.sql) != ""])
    error_message = "A dataset sql must not be blank."
  }

  validation {
    condition     = alltrue([for _, d in var.datasets : d.table == null ? true : d.table.name != null && d.table.name != ""])
    error_message = "A dataset table needs a non-empty name."
  }

  validation {
    condition     = alltrue([for _, d in var.datasets : contains(["DIRECT_QUERY", "SPICE"], d.import_mode)])
    error_message = "A dataset import_mode must be DIRECT_QUERY or SPICE."
  }

  validation {
    condition     = alltrue([for _, d in var.datasets : length(d.columns) >= 1])
    error_message = "Each dataset needs at least one column."
  }

  validation {
    condition     = alltrue(flatten([for _, d in var.datasets : [for c in d.columns : contains(["STRING", "INTEGER", "DECIMAL", "DATETIME", "BIT", "BOOLEAN", "JSON", "SEMISTRUCT"], c.type)]]))
    error_message = "A dataset column type must be one of STRING, INTEGER, DECIMAL, DATETIME, BIT, BOOLEAN, JSON, SEMISTRUCT."
  }
}

variable "owner_principals" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "擁有者的 QuickSight user 或 group ARN（`arn:aws:quicksight:<identity region>:<account>:user/<namespace>/<name>` 或 `group/<namespace>/<name>`）。對每個 data source 與 dataset 取得檢視、修改、刪除與改權限的 action（data source 6 個、dataset 10 個）。不能同時出現在 `reader_principals`。QuickSight 帳號、user、group 由 module 以外管理。"

  validation {
    condition     = alltrue([for p in var.owner_principals : can(regex("^arn:aws[a-z-]*:quicksight:[a-z0-9-]+:[0-9]{12}:(user|group)/[^/]+/.+$", p))])
    error_message = "owner_principals must be QuickSight user or group ARNs (arn:<partition>:quicksight:<region>:<account>:user|group/<namespace>/<name>)."
  }
}

variable "reader_principals" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "唯讀使用者的 QuickSight user 或 group ARN，格式同 `owner_principals`。對每個 data source 取得檢視與 pass 的 action（3 個），對每個 dataset 取得檢視、pass 與查詢 ingestion 的 action（5 個）。不能同時出現在 `owner_principals`。"

  validation {
    condition     = alltrue([for p in var.reader_principals : can(regex("^arn:aws[a-z-]*:quicksight:[a-z0-9-]+:[0-9]{12}:(user|group)/[^/]+/.+$", p))])
    error_message = "reader_principals must be QuickSight user or group ARNs (arn:<partition>:quicksight:<region>:<account>:user|group/<namespace>/<name>)."
  }

  validation {
    condition     = length(setintersection(toset(var.reader_principals), toset(var.owner_principals))) == 0
    error_message = "A principal cannot be in both owner_principals and reader_principals."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "每個 resource 的 tag；`Name` 由 module 加上。"
}
