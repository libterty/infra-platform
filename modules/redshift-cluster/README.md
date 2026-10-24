# redshift-cluster

建一個 provisioned Redshift cluster（RA3）：放在 VPC 內、不公開，用客戶管理的 KMS key 加密，管理者密碼由 Redshift 產生並放在 Secrets Manager。含 subnet group、parameter group（`require_ssl = true`）與寫到 CloudWatch Logs 的稽核 log。

跟 [`redshift-serverless`](../redshift-serverless/README.md) 沒有共用 resource，但兩個 module 發布同名的 `endpoint_address`、`port`、`database_name`、`admin_secret_arn`，呼叫端可以依模式二選一。

## 用法

```hcl
module "warehouse" {
  source = "git::https://github.com/<org>/<repo>.git//modules/redshift-cluster?ref=redshift-cluster-v0.1.0"

  name          = "alpha-dev-wh"
  database_name = "analytics"
  kms_key_arn   = module.key.key_arn

  node_type       = "ra3.large"
  number_of_nodes = 1

  subnet_ids         = module.vpc.subnet_ids_data
  security_group_ids = [module.sg_redshift.id]
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 密碼 | `manage_master_password = true`，secret 用 `kms_key_arn` 加密；沒有任何密碼變數 |
| 公開 | `publicly_accessible = false`，沒有開關 |
| 加密 | `encrypted = true`，`kms_key_id` 是必填輸入 `kms_key_arn` |
| 傳輸 | parameter group 固定 `require_ssl = true` |
| 稽核 log | `aws_redshift_logging` 寫 CloudWatch Logs（`/aws/redshift/cluster/<name>/<類型>`），`connectionlog`、`userlog`、`useractivitylog` 全開，同時設 `enable_user_activity_logging = true`；不寫 S3 |
| final snapshot | `skip_final_snapshot` 預設 `false`，snapshot 名稱 `<name>-final` |
| 連線埠 | 5439 |
| tag | 給定的 `tags` 加上 `Name` |

## 注意

- node type 只收 `ra3.large`、`ra3.xlplus`、`ra3.4xlarge`、`ra3.16xlarge`。`number_of_nodes = 1`（single-node）只有 `ra3.large`、`ra3.xlplus` 可以；官方文件不建議 production 用 single-node，single-node 轉 multi-node 只能做 classic resize。
- `skip_final_snapshot = false` 時 snapshot 名稱固定是 `<name>-final`，同名 snapshot 已存在會讓 destroy 失敗；重建同名 cluster 前先刪掉舊的 final snapshot 或改用別的 `name`。
- `automated_snapshot_retention_days` 範圍 0–35，0 會關掉自動 snapshot。
- subnet 至少兩個、分屬不同 AZ；module 只能數 subnet，AZ 分布由呼叫端保證。
- `enhanced_vpc_routing` 開著（預設）時，COPY、UNLOAD、Spectrum 的流量走 VPC，所以 VPC 要有 S3 gateway endpoint（以及 Glue 的 interface endpoint 或 NAT）。
- `parameters` 不能設 `require_ssl` 與 `enable_user_activity_logging`，這兩個由 module 管。parameter group 的 family 固定 `redshift-2.0`。
- `iam_role_arns` 與 `default_iam_role_arn` 由呼叫端建立 role 後傳入，這個 module 不建 IAM 與 security group。
- 執行 apply 的身分需要 `iam:CreateServiceLinkedRole`（第一次建立 Redshift 時）、`iam:PassRole`（`iam_role_arns` 的 role）、`kms:CreateGrant`，以及讀 secret 的 `secretsmanager:GetSecretValue`。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

dc2 與 rg node type、snapshot copy、暫停排程、HSM、usage limit、密碼輸入。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | cluster 識別名稱，也是 subnet group 與 parameter group 的名稱。1–63 字元，限小寫英文字母、數字、`-`，開頭要是字母，不能連續兩個 `-` 或以 `-` 結尾。 |
| `database_name` | `string` | 無 | 是 | cluster 建立的第一個資料庫名稱，1–64 字元，限小寫英文字母、數字、`_`，開頭要是字母。 |
| `master_username` | `string` | `"dbadmin"` | 否 | 管理者帳號名稱（預設 `dbadmin`）。密碼由 Redshift 產生並放在 Secrets Manager，module 沒有密碼變數。 |
| `node_type` | `string` | 無 | 是 | node 類型，只收 RA3：`ra3.large`、`ra3.xlplus`、`ra3.4xlarge`、`ra3.16xlarge`。 |
| `number_of_nodes` | `number` | `1` | 否 | node 數量，1–128（預設 1）。1 個 node 是 single-node cluster，只有 `ra3.large`、`ra3.xlplus` 可以；官方文件不建議 production 用 single-node。每種 node type 的建立上限不同（`ra3.large`、`ra3.xlplus` 16、`ra3.4xlarge` 32），超過會由 AWS 回錯。 |
| `kms_key_arn` | `string` | 無 | 是 | cluster 資料與管理者 secret 加密用的客戶管理 KMS key ARN，必填。key policy 要讓 Redshift 能建立 grant（執行 apply 的身分需要 `kms:CreateGrant`）。 |
| `iam_role_arns` | `set(string)` | `[]` | 否 | 掛到 cluster 的 IAM role ARN（例如讀 S3 curated、Glue catalog 的 role）。role 由呼叫端建立，這個 module 不建 IAM。 |
| `default_iam_role_arn` | `string` | `null` | 否 | cluster 的預設 IAM role ARN，必須也在 `iam_role_arns` 裡；`null` 表示不設預設 role。 |
| `subnet_ids` | `list(string)` | 無 | 是 | cluster 的 subnet，至少兩個、分屬不同 AZ（module 只能數 subnet，AZ 分布由呼叫端保證）。 |
| `security_group_ids` | `list(string)` | 無 | 是 | cluster 的 security group，至少一個，由 network stack 建立。 |
| `enhanced_vpc_routing` | `bool` | `true` | 否 | 是否開 enhanced VPC routing，讓 COPY、UNLOAD 與 Spectrum 的流量走 VPC（預設 `true`）。S3 與 Glue 要有 VPC endpoint 或 NAT。 |
| `automated_snapshot_retention_days` | `number` | `7` | 否 | 自動 snapshot 的保留天數，0–35（預設 7）；0 表示關閉自動 snapshot。 |
| `skip_final_snapshot` | `bool` | `false` | 否 | destroy 時是否跳過最終 snapshot（預設 `false`）。不跳過時 snapshot 名稱是 `<name>-final`，同名 snapshot 已存在會讓 destroy 失敗。 |
| `multi_az` | `bool` | `false` | 否 | 是否啟用 Multi-AZ（預設 `false`）。官方文件說明 Multi-AZ 支援 RA3 與 RG；實際限制由 AWS 回錯。 |
| `parameters` | `map(string)` | `{}` | 否 | 額外的 cluster parameter（例如 `datestyle`、`search_path`、`max_concurrency_scaling_clusters`）。`require_ssl` 與 `enable_user_activity_logging` 由 module 管，不能在這裡設。 |
| `tags` | `map(string)` | `{}` | 否 | cluster、subnet group、parameter group 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `endpoint_address` | cluster 的連線 DNS 位址（VPC 內）。 |
| `port` | cluster 的連線埠。 |
| `database_name` | cluster 的第一個資料庫名稱。 |
| `admin_secret_arn` | Redshift 代管的管理者帳密 secret 的 ARN（Secrets Manager）。 |
| `cluster_identifier` | cluster 識別名稱。 |
| `arn` | cluster 的 ARN。 |
<!-- END_TF_DOCS -->
