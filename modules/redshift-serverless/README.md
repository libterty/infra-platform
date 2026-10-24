# redshift-serverless

建一個 Redshift Serverless 資料倉儲：一個 namespace 加一個 workgroup，放在 VPC 內、不公開，用客戶管理的 KMS key 加密，管理者密碼由 Redshift 產生並放在 Secrets Manager。可選每月 RPU-小時用量上限。固定連線一律要 SSL，稽核 log 寫 CloudWatch Logs。

跟 [`redshift-cluster`](../redshift-cluster/README.md)（provisioned）沒有共用 resource，但兩個 module 發布同名的 `endpoint_address`、`port`、`database_name`、`admin_secret_arn`，呼叫端可以依模式二選一。

## 用法

```hcl
module "warehouse" {
  source = "git::https://github.com/<org>/<repo>.git//modules/redshift-serverless?ref=redshift-serverless-v0.1.0"

  name        = "alpha-dev-wh"
  db_name     = "analytics"
  kms_key_arn = module.key.key_arn

  base_capacity         = 4
  max_capacity          = 8
  usage_limit_rpu_hours = 100

  subnet_ids         = module.vpc.subnet_ids_data
  security_group_ids = [module.sg_redshift.id]
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 密碼 | `manage_admin_password = true`，secret 用 `kms_key_arn` 加密；沒有任何密碼變數 |
| 公開 | `publicly_accessible = false`，沒有開關 |
| 加密 | namespace 的 `kms_key_id` 是必填輸入 `kms_key_arn` |
| 傳輸 | workgroup 的 `config_parameter` 固定 `require_ssl = true` |
| 稽核 log | `log_exports` 匯出到 CloudWatch Logs（`/aws/redshift/serverless/<namespace>/<類型>`），預設三種全開，至少要一個 |
| 用量上限 | `usage_limit_rpu_hours` 有值才建；固定 `serverless-compute`、每月、達上限 `deactivate` |
| tag | 給定的 `tags` 加上 `Name` |

## 注意

- **namespace 沒有 final snapshot，刪除即丟資料。** `aws_redshiftserverless_namespace` 沒有任何 snapshot 屬性，`terraform destroy` 或 `name` 變動造成的 replace 會直接刪掉資料；需要保留資料時，destroy 前自己在 Redshift 建 snapshot 或 `UNLOAD` 到 S3。這個 module 刻意不做 snapshot 與還原。
- `base_capacity` 可以是 4，或 8–512 之間 8 的倍數（東京 region 的上限是 512）。4 RPU 建議資料量 32 TB 以內、每張表 100 欄以內；擴到 8 以上就不會自動縮回 4。`max_capacity` 不給就不設上限。
- subnet 數量：沒開 `enhanced_vpc_routing` 至少 2 個 subnet 跨 2 個 AZ，開了（預設）至少 3 個跨 3 個 AZ。module 只能數 subnet，AZ 分布要由呼叫端保證；provider 文件寫「設定時要 3 個 subnet、3 個 AZ」，跟 AWS 文件不同，以 AWS 文件為準。每個 subnet 要有足夠空閒 IP（4 RPU 約 9 個，擴容時更多）。
- `enhanced_vpc_routing` 開著時，COPY、UNLOAD、Spectrum 的流量走 VPC，所以 VPC 要有 S3 gateway endpoint（以及 Glue 的 interface endpoint 或 NAT）。
- `usage_limit_rpu_hours` 達到上限會停止查詢（`deactivate`），不是只記錄；要觀察不要擋，要改 module。
- `config_parameters` 不能設 `require_ssl` 與 `enable_user_activity_logging`；含 `useractivitylog` 時 module 會自動設後者。
- `iam_role_arns` 與 `default_iam_role_arn` 由呼叫端建立 role 後傳入，這個 module 不建 IAM 與 security group。
- 執行 apply 的身分需要 `iam:CreateServiceLinkedRole`（第一次建立 Redshift 時）、`iam:PassRole`（`iam_role_arns` 的 role）、`kms:CreateGrant`，以及讀 secret 的 `secretsmanager:GetSecretValue`。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

snapshot 與還原、custom domain、endpoint access、resource policy、datashare、price-performance target、密碼輸入。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | namespace 與 workgroup 共用的名稱，3–64 字元，限小寫英文字母、數字、`-`。 |
| `db_name` | `string` | 無 | 是 | namespace 建立的第一個資料庫名稱，1–64 字元，限小寫英文字母、數字、`_`，開頭要是字母。 |
| `admin_username` | `string` | `"dbadmin"` | 否 | 管理者帳號名稱（預設 `dbadmin`）。密碼由 Redshift 產生並放在 Secrets Manager，module 沒有密碼變數。 |
| `kms_key_arn` | `string` | 無 | 是 | namespace 資料與管理者 secret 加密用的客戶管理 KMS key ARN，必填。key policy 要讓 Redshift 能建立 grant（執行 apply 的身分需要 `kms:CreateGrant`）。 |
| `iam_role_arns` | `set(string)` | `[]` | 否 | 掛到 namespace 的 IAM role ARN（例如讀 S3 curated、Glue catalog 的 role）。role 由呼叫端建立，這個 module 不建 IAM。 |
| `default_iam_role_arn` | `string` | `null` | 否 | namespace 的預設 IAM role ARN，必須也在 `iam_role_arns` 裡；`null` 表示不設預設 role。 |
| `base_capacity` | `number` | `4` | 否 | workgroup 的 base 容量（RPU），可以是 4，或 8–512 之間 8 的倍數（預設 4）。4 RPU 建議資料量 32 TB、每張表 100 欄以內；擴到 8 以上就不會自動縮回 4。 |
| `max_capacity` | `number` | `null` | 否 | workgroup 自動擴充的容量上限（RPU），整數、不小於 `base_capacity`、最多 512；`null` 表示不設上限。 |
| `subnet_ids` | `list(string)` | 無 | 是 | workgroup 的 subnet。沒開 `enhanced_vpc_routing` 至少 2 個、開了至少 3 個，而且要分屬不同 AZ（module 只能數 subnet，AZ 分布由呼叫端保證）；每個 subnet 要有足夠的空閒 IP（4 RPU 約 9 個）。 |
| `security_group_ids` | `list(string)` | 無 | 是 | workgroup 的 security group，至少一個，由 network stack 建立。 |
| `enhanced_vpc_routing` | `bool` | `true` | 否 | 是否開 enhanced VPC routing，讓 COPY、UNLOAD 與 Spectrum 的流量走 VPC（預設 `true`）。開了需要 3 個 subnet 跨 3 個 AZ，S3 與 Glue 要有 VPC endpoint 或 NAT。 |
| `log_exports` | `set(string)` | `[ "connectionlog", "userlog", "useractivitylog" ]` | 否 | 匯出到 CloudWatch Logs 的稽核 log 類型，至少一個，可選 `connectionlog`、`userlog`、`useractivitylog`（預設全開）。含 `useractivitylog` 時 module 會自動設 `enable_user_activity_logging = true`。 |
| `usage_limit_rpu_hours` | `number` | `null` | 否 | 每月可用的 RPU-小時上限，必須大於 0；達到上限會 `deactivate`（停止查詢，直到下個月或調高上限）。`null` 表示不設用量上限。 |
| `config_parameters` | `map(string)` | `{}` | 否 | 額外的 workgroup config parameter（例如 `datestyle`、`search_path`、`max_query_execution_time`）。`require_ssl` 與 `enable_user_activity_logging` 由 module 管，不能在這裡設。 |
| `tags` | `map(string)` | `{}` | 否 | namespace 與 workgroup 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `endpoint_address` | workgroup 的連線 DNS 位址（VPC 內）。 |
| `port` | workgroup 的連線埠。 |
| `database_name` | namespace 的第一個資料庫名稱。 |
| `admin_secret_arn` | Redshift 代管的管理者帳密 secret 的 ARN（Secrets Manager）。 |
| `namespace_name` | namespace 名稱。 |
| `workgroup_name` | workgroup 名稱。 |
| `workgroup_arn` | workgroup 的 ARN。 |
<!-- END_TF_DOCS -->
