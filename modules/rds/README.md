# rds

建一個 PostgreSQL 資料庫，三種型態擇一：一般 RDS（`rds`）、Aurora provisioned（`aurora`）、Aurora Serverless v2（`aurora_serverless`）。RDS Proxy 是選項。不管選哪種，輸出的端點與識別碼格式都一樣，下游不用知道選了哪種。

## 用法

```hcl
module "db" {
  source = "git::https://github.com/<org>/<repo>.git//modules/rds?ref=rds-v0.1.0"

  name           = "alpha-dev-db"
  deployment     = "aurora_serverless"
  engine_version = "16.4"
  database_name  = "app"

  serverless = { min_capacity = 0.5, max_capacity = 4 }

  subnet_ids         = local.in_lists["subnet_ids_data"]
  security_group_ids = [local.in["sg_db_id"]]
  kms_key_arn        = local.in["kms_key_arn"]

  # 開 Proxy 與 Enhanced Monitoring 的 role 都從 iam-base 傳入，module 不建 IAM
  proxy = {
    security_group_ids = [local.in["sg_db_proxy_id"]]
    role_arn           = local.in["role_rds_proxy_arn"]
  }
  monitoring = { role_arn = local.in["role_rds_monitoring_arn"] }

  sns_topic_arns = [local.in["alarm_topic_arn"]]
}
```

完整範例見 [`examples/rds/`](./examples/rds/main.tf) 與 [`examples/aurora-serverless-proxy/`](./examples/aurora-serverless-proxy/main.tf)。

## 三種型態對照

| | `rds` | `aurora` | `aurora_serverless` |
|---|---|---|---|
| 型態物件 | `rds` | `aurora` | `serverless` |
| 主要資源 | `aws_db_instance.this` | `aws_rds_cluster.this` ＋ `aws_rds_cluster_instance.this` | 同 aurora，instance class 固定 `db.serverless` |
| 參數群組 family | `postgres<major>` | `aurora-postgresql<major>` | 同 aurora |
| reader | 不支援 | `reader_count`（預設 1） | `reader_count`（預設 0） |
| log group | `/aws/rds/instance/<name>/postgresql` | `/aws/rds/cluster/<name>/postgresql` | 同 aurora |
| `identifier_type` | `instance` | `cluster` | `cluster` |
| 連線數告警門檻 | 必填 | 必填 | 沒給時由 `max_capacity` 推算 |

選了哪個型態就必須給對應的物件，另外兩個必須是 null（`deployment` 的交叉 validation）。`cluster_parameters` 只給 Aurora 用，`deployment = "rds"` 時必須為空。

`aurora` 與 `aurora_serverless` 共用同一組資源位址，互換是就地修改。

## 注意

- **`rds` 與 Aurora 互換是資料遷移，不是改一個變數。** 兩者的資源型別不同，互換會 destroy 加 create，被 `deletion_protection` 擋下。要換就先用 snapshot 還原或 DMS 搬資料，再切換呼叫端的連線設定。
- **一般 RDS 的端點是 `aws_db_instance.this.address`，不是 `.endpoint`**（後者是 `host:port`）。`writer_endpoint` 與 `reader_endpoint` 都不帶 port，port 看 `port` 輸出。
- **密碼由 RDS 放在 Secrets Manager**（`manage_master_user_password = true`），module 沒有任何 password 變數。`master_user_secret_arn` 是 master 帳號的 secret。應用程式直接用 master 帳號有風險：權限過大、secret 輪替時連線會斷。第一版不管應用程式專用帳號，要的話在資料庫內自己建帳號。
- **Proxy 的 role 與讀 secret 的 policy 都不在這個 module。** role 由 `iam-base` 建，讀 master secret 的 policy 在 secret 存在之後由 `iam-app` 附加。
- `proxy.role_arn` 宣告成 `optional(string)`，由 validation 擋 null：必填屬性缺漏時 Terraform 在型別轉換階段就報錯，負向測試鎖不住這件事。
- `app_endpoint` 與 `app_reader_endpoint` 是給應用程式的端點：有 Proxy 時是 Proxy（reader 優先用 read-only endpoint，沒有就用 Proxy 本身），沒有 Proxy 時是 DB 本身。
- `shared_preload_libraries` 是靜態參數，module 設成 `pending-reboot`；其餘預設參數是動態參數。呼叫端另外給靜態參數時，module 用 `immediate` 套用，AWS 會拒絕，這種情況目前要自己處理（**未驗證**）。
- 告警的 `connections_threshold`：`aurora_serverless` 沒給時為 `floor(min(max_capacity × 2 GiB ÷ 9,531,392, 5000) × 0.8)`；`rds` 與 `aurora` 的 `max_connections` 取決於 instance class，離線算不出來，必填。
- **Data API（`data_api = true`）只給 Aurora。** Bedrock Knowledge Base 的 Aurora 向量儲存只能經 Data API 存取；KB 要的 cluster ARN 就是既有的 `arn` 輸出。Data API 對 Aurora PostgreSQL 有版本要求（AWS 文件寫 13.12、14.9、15.4、16.1 以上這類），**未查證**，沒有做成 validation（design §7.3）。
- `deployment` 與 `database_name` 兩個輸出直接取變數，不讀 resource 屬性，plan 時就是已知值。
- 以下都是 mock 驗不到的，列在 design §7.3：型態互換的實際行為、`min_capacity = 0`（閒置自動暫停）跟 engine 版本的關係、Aurora 自動 minor 升級造成的 `engine_version` 差異。

## 刻意不做

- 一般 RDS 的 read replica、RDS Multi-AZ DB cluster、同一個 cluster 混用 provisioned 與 serverless instance。
- 應用程式專用帳號與 Proxy 的 IAM 認證。
- MySQL。
- 任何 IAM 資源與 security group，以及自行產生密碼的資源（`scripts/validate.sh` 的 S4、S7 會擋）。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | 完整名稱，小寫英數與單一連字號，最長 50 字 |
| `deployment` | `string` | 無 | 是 | `rds`、`aurora` 或 `aurora_serverless` |
| `engine_version` | `string` | 無 | 是 | PostgreSQL `major.minor`（13–17），major 決定參數群組 family |
| `database_name` | `string` | 無 | 是 | 初始資料庫名稱 |
| `master_username` | `string` | `"dbadmin"` | 否 | master 帳號名稱 |
| `subnet_ids` | `list(string)` | 無 | 是 | data tier subnet，至少兩個 |
| `security_group_ids` | `list(string)` | 無 | 是 | DB 的 SG（network stack 建） |
| `kms_key_arn` | `string` | `null` | 否 | 儲存與 Performance Insights 的 KMS key；null 用 `aws/rds` |
| `master_user_secret_kms_key_arn` | `string` | `null` | 否 | master secret 的 KMS key；null 用 `aws/secretsmanager` |
| `backup_retention_days` | `number` | `7` | 否 | 1–35 |
| `backup_window` | `string` | `"18:00-19:00"` | 否 | UTC |
| `maintenance_window` | `string` | `"sun:19:00-sun:20:00"` | 否 | UTC |
| `deletion_protection` | `bool` | `true` | 否 | |
| `data_api` | `bool` | `false` | 否 | 在 Aurora cluster 開 RDS Data API（`enable_http_endpoint`），Bedrock Knowledge Base 需要；只限 `aurora`、`aurora_serverless`，`rds` 配 `true` 會被 validation 擋下 |
| `skip_final_snapshot` | `bool` | `false` | 否 | |
| `cluster_parameters` | `map(string)` | `{}` | 否 | Aurora cluster 參數；`rds` 時必須為空 |
| `instance_parameters` | `map(string)` | `{}` | 否 | rds 併入唯一的參數群組；Aurora 非空才另建 instance 參數群組 |
| `performance_insights_retention_days` | `number` | `7` | 否 | 7、31 的倍數（最多 713）或 731 |
| `monitoring` | `object({ interval, role_arn })` | `null` | 否 | Enhanced Monitoring；`interval` 預設 60；null 不開 |
| `log_retention_days` | `number` | `30` | 否 | PostgreSQL 與 Proxy log group 保留天數 |
| `log_kms_key_arn` | `string` | `null` | 否 | log group 的 KMS key |
| `sns_topic_arns` | `list(string)` | 無 | 是 | 告警的 `alarm_actions` 與 `ok_actions`，至少一個 |
| `tags` | `map(string)` | `{}` | 否 | `Name` 由 module 加上 |
| `rds` | `object` | `null` | 否 | `instance_class`（必填）、`allocated_storage`（20）、`max_allocated_storage`（null）、`multi_az`（false）、`storage_type`（`gp3`） |
| `aurora` | `object` | `null` | 否 | `instance_class`（必填，不可為 `db.serverless`）、`reader_count`（1，0–15） |
| `serverless` | `object` | `null` | 否 | `min_capacity`、`max_capacity`（ACU，0.5 的倍數，最大 256）、`reader_count`（0，0–15） |
| `proxy` | `object` | `null` | 否 | `security_group_ids`、`role_arn`（實質必填）、`require_tls`（true）、`idle_client_timeout`（1800）、`max_connections_percent`（50）、`max_idle_connections_percent`（25）、`debug_logging`（false）；null 不建 Proxy |
| `alarm_config` | `object` | `{}` | 否 | `cpu_threshold`（80）、`freeable_memory_bytes`（209715200）、`connections_threshold`（rds、aurora 必填）、`replica_lag_threshold_ms`（1000）、`proxy_borrowed_percent`（80）、`proxy_pinned_percent`（20） |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `writer_endpoint` | `string` | rds：instance `address`；Aurora：cluster `endpoint` |
| `reader_endpoint` | `string` | rds：等於 writer；Aurora：cluster `reader_endpoint` |
| `has_reader` | `bool` | rds 為 false；Aurora 為 `reader_count > 0` |
| `proxy_endpoint` | `string` | 沒開 Proxy 時為 null |
| `app_endpoint` | `string` | 有 Proxy 是 Proxy，否則是 writer |
| `app_reader_endpoint` | `string` | 有 read-only endpoint 用它；有 Proxy 沒有 read-only 用 Proxy；沒開 Proxy 用 `reader_endpoint` |
| `port` | `number` | 5432 |
| `master_user_secret_arn` | `string` | RDS 管理的 master secret ARN |
| `db_identifier` | `string` | instance 或 cluster 識別碼 |
| `identifier_type` | `string` | `"instance"` 或 `"cluster"` |
| `cluster_id` | `string` | rds 時為 null |
| `instance_ids` | `list(string)` | 依序，index 0 是 writer |
| `cloudwatch_dimension` | `object` | `{ name, value }`，name 為 `DBInstanceIdentifier` 或 `DBClusterIdentifier` |
| `arn` | `string` | instance 或 cluster ARN |
| `resource_id` | `string` | `DbiResourceId` 或 `DbClusterResourceId` |
| `alarm_arns` | `map(string)` | key 為 `cpu_high_writer`、`connections_high`、`proxy_pinned_high` 這類 |
| `deployment` | `string` | 輸入的 `deployment` 原樣輸出：`rds`、`aurora` 或 `aurora_serverless` |
| `database_name` | `string` | 輸入的 `database_name` 原樣輸出 |

## 測試

```bash
scripts/validate.sh modules/rds
```

測試在 plan 階段用 `override_resource { override_during = plan }` 補上 computed 值（端點、`master_user_secret` 這個 nested list、`random_id` 的 hex）；mock 對沒設值的 computed 屬性會填隨機字串，所以「computed 屬性為 null」這類斷言在 mock 下測不了。
