# rds

建一個 PostgreSQL 資料庫，三種型態擇一：一般 RDS（`rds`）、Aurora provisioned（`aurora`）、Aurora Serverless v2（`aurora_serverless`）。RDS Proxy 可選。不管選哪種，輸出的端點與識別碼格式都一樣，下游不用知道選了哪種。

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

選了哪個型態就必須給對應的物件，另外兩個必須是 null（由 `deployment` 的交叉 validation 檢查）。`cluster_parameters` 只給 Aurora 用，`deployment = "rds"` 時必須為空。

`aurora` 與 `aurora_serverless` 共用同一組資源位址，互換是就地修改。

## 注意

- **`rds` 與 Aurora 互換是資料遷移，不是改一個變數。** 兩者的資源型別不同，互換會變成 destroy 再 create，然後被 `deletion_protection` 擋下。要換就先用 snapshot 還原或 DMS 搬資料，再切換呼叫端的連線設定。
- **一般 RDS 的端點是 `aws_db_instance.this.address`，不是 `.endpoint`**（後者是 `host:port`）。`writer_endpoint` 與 `reader_endpoint` 都不帶 port，port 看 `port` 輸出。
- **密碼由 RDS 放在 Secrets Manager**（`manage_master_user_password = true`），module 沒有任何 password 變數。`master_user_secret_arn` 是 master 帳號的 secret。應用程式直接用 master 帳號有風險：權限過大、secret 輪替時連線會斷。第一版不處理應用程式專用帳號，需要的話自己在資料庫裡建。
- **Proxy 的 role 與讀 secret 的 policy 都不在這個 module。** role 由 `iam-base` 建，讀 master secret 的 policy 在 secret 存在之後由 `iam-app` 附加。
- `proxy.role_arn` 宣告成 `optional(string)`，再由 validation 擋 null。原因是必填屬性缺漏時，Terraform 在型別轉換階段就報錯，負向測試沒辦法驗證這個錯誤。
- `app_endpoint` 與 `app_reader_endpoint` 是給應用程式的端點：有 Proxy 時是 Proxy（reader 優先用 read-only endpoint，沒有就用 Proxy 本身），沒有 Proxy 時是 DB 本身。
- `shared_preload_libraries` 是靜態參數，module 設成 `pending-reboot`；其餘預設參數是動態參數。呼叫端另外給靜態參數時，要列進 `static_parameter_names`（0.2.0 起），否則 module 用 `immediate` 套用，AWS 會拒絕（**未驗證**）。
- 告警的 `connections_threshold`：`aurora_serverless` 沒給時為 `floor(min(max_capacity × 2 GiB ÷ 9,531,392, 5000) × 0.8)`；`rds` 與 `aurora` 的 `max_connections` 取決於 instance class，離線算不出來，所以必填。
- **Data API（`data_api = true`）只給 Aurora。** Bedrock Knowledge Base 的 Aurora 向量儲存只能經 Data API 存取；KB 要的 cluster ARN 就是既有的 `arn` 輸出。Data API 對 Aurora PostgreSQL 有版本要求（AWS 文件寫 13.12、14.9、15.4、16.1 以上這類），**未查證**，沒有做成 validation（design §7.3）。
- `deployment` 與 `database_name` 兩個輸出直接取變數，不讀 resource 屬性，plan 時就是已知值。
- 下面這些 mock 驗不到，列在 design §7.3：型態互換的實際行為、`min_capacity = 0`（閒置自動暫停）跟 engine 版本的關係、Aurora 自動 minor 升級造成的 `engine_version` 差異。

- **static 參數要自己列。** module 只知道 `shared_preload_libraries` 是 static；其他 static 參數（例如 `cron.database_name`）如果不列進 `static_parameter_names`，會被送成 `immediate`，apply 時 RDS 會拒絕。列了但沒有出現在 `cluster_parameters`／`instance_parameters` 的名稱不會有任何效果。static 參數的變更要重開機才生效，重開時機由呼叫端決定。

## 刻意不做

- 一般 RDS 的 read replica、RDS Multi-AZ DB cluster、同一個 cluster 混用 provisioned 與 serverless instance。
- 應用程式專用帳號與 Proxy 的 IAM 認證。
- MySQL。
- 任何 IAM 資源與 security group，以及自行產生密碼的資源（`scripts/validate.sh` 的 S4、S7 會擋）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | 完整名稱，用作 DB 識別碼，也是所有相關資源名稱的基底。小寫字母開頭，限小寫英數與單一連字號，不可以連字號結尾，最長 50 字元。 |
| `deployment` | `string` | 無 | 是 | 資料庫型態：`rds`（單一 instance）、`aurora`（provisioned cluster）或 `aurora_serverless`（Serverless v2 cluster）。對應的物件（`rds`、`aurora`、`serverless`）必填，另外兩個必須是 `null`。 |
| `engine_version` | `string` | 無 | 是 | PostgreSQL 版本，格式 `major.minor`（例如 `16.4`），major 限 13–17，決定參數群組 family。 |
| `database_name` | `string` | 無 | 是 | 初始資料庫名稱，小寫字母開頭，限小寫英數與 `_`，最長 63 字元。 |
| `master_username` | `string` | `"dbadmin"` | 否 | master 帳號名稱。密碼由 RDS 產生並放在 Secrets Manager，module 沒有密碼變數。 |
| `subnet_ids` | `list(string)` | 無 | 是 | data tier 的 subnet，至少兩個、分屬不同 AZ。 |
| `security_group_ids` | `list(string)` | 無 | 是 | DB 的 security group，由 network stack 建立。 |
| `kms_key_arn` | `string` | `null` | 否 | 儲存與 Performance Insights 用的 KMS key；`null` 時用 AWS managed key（`aws/rds`）。 |
| `master_user_secret_kms_key_arn` | `string` | `null` | 否 | master 帳號 secret 的 KMS key；`null` 時用 `aws/secretsmanager`。 |
| `backup_retention_days` | `number` | `7` | 否 | 自動備份保留天數，1–35。 |
| `backup_window` | `string` | `"18:00-19:00"` | 否 | 每日備份時段（UTC）。預設 `18:00-19:00` 是台灣時間 02:00–03:00。 |
| `maintenance_window` | `string` | `"sun:19:00-sun:20:00"` | 否 | 每週維護時段（UTC）。預設 `sun:19:00-sun:20:00` 是台灣時間週一 03:00–04:00。 |
| `deletion_protection` | `bool` | `true` | 否 | 是否擋下 instance 或 cluster 的刪除。 |
| `data_api` | `bool` | `false` | 否 | 在 Aurora cluster 開 RDS Data API（`enable_http_endpoint`），Bedrock Knowledge Base 需要。只限 `aurora`、`aurora_serverless`；`deployment = "rds"` 時給 `true` 會被擋下。 |
| `skip_final_snapshot` | `bool` | `false` | 否 | destroy 時是否跳過最終 snapshot。 |
| `cluster_parameters` | `map(string)` | `{}` | 否 | Aurora 的 cluster 參數，蓋過 module 同名的預設值。`deployment = "rds"` 時必須為空（改用 `instance_parameters`）。 |
| `instance_parameters` | `map(string)` | `{}` | 否 | instance 參數。`rds` 時併入 module 預設值、放在唯一的參數群組；Aurora 時非空才另建 instance 參數群組。 |
| `static_parameter_names` | `set(string)` | `[]` | 否 | `cluster_parameters`、`instance_parameters` 裡屬於 static 的參數名稱（例如 `cron.database_name`），改用 `pending-reboot` 套用而不是 `immediate`。跟內建的 `shared_preload_libraries`（一律視為 static）取聯集。0.2.0 起。 |
| `performance_insights_retention_days` | `number` | `7` | 否 | Performance Insights 保留天數：`7`、31 的倍數（最多 713）或 `731`。 |
| `monitoring` | `object` | `null` | 否 | Enhanced Monitoring；`null` 時不開。欄位：`role_arn`（必填，來自 `iam-base` stack）、`interval`（秒，預設 `60`，限 `1`、`5`、`10`、`15`、`30`、`60`）。 |
| `log_retention_days` | `number` | `30` | 否 | PostgreSQL 與 Proxy log group 的保留天數。 |
| `log_kms_key_arn` | `string` | `null` | 否 | log group 的 KMS key；`null` 時用 CloudWatch 預設加密。 |
| `sns_topic_arns` | `list(string)` | 無 | 是 | 告警的 `alarm_actions` 與 `ok_actions` 要送的 SNS topic ARN，至少一個。 |
| `tags` | `map(string)` | `{}` | 否 | 可加 tag 的資源都會帶上的 tag；`Name` 由 module 加上。 |
| `rds` | `object` | `null` | 否 | `deployment = "rds"` 時的設定，其他型態必須是 `null`。欄位：`instance_class`（必填）、`allocated_storage`（預設 `20`）、`max_allocated_storage`（預設 `null`）、`multi_az`（預設 `false`）、`storage_type`（預設 `gp3`）。 |
| `aurora` | `object` | `null` | 否 | `deployment = "aurora"` 時的設定，其他型態必須是 `null`。欄位：`instance_class`（必填，以 `db.` 開頭，不可為 `db.serverless`）、`reader_count`（預設 `1`，0–15）。 |
| `serverless` | `object` | `null` | 否 | `deployment = "aurora_serverless"` 時的設定，其他型態必須是 `null`。欄位：`min_capacity`、`max_capacity`（必填，單位 ACU，0.5 的倍數，`0 <= min_capacity <= max_capacity <= 256`）、`reader_count`（預設 `0`，0–15）。 |
| `proxy` | `object` | `null` | 否 | RDS Proxy；`null` 時不建。`role_arn` 實質必填。欄位見〈`proxy` 欄位〉。 |
| `alarm_config` | `object` | `{}` | 否 | 告警門檻。`connections_threshold` 在 `rds`、`aurora` 必填。欄位見〈`alarm_config` 欄位〉。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `writer_endpoint` | writer 的 host，不帶 port：`rds` 是 instance 的 `address`，Aurora 是 cluster `endpoint`。 |
| `reader_endpoint` | reader 的 host：`rds` 等於 `writer_endpoint`，Aurora 是 cluster 的 `reader_endpoint`。 |
| `has_reader` | 至少有一個 reader 時為 `true`：`rds` 一律 `false`，Aurora 是 `reader_count > 0`。 |
| `proxy_endpoint` | RDS Proxy 端點；沒開 Proxy 時為 `null`。 |
| `app_endpoint` | 應用程式寫入要連的 host：有 Proxy 時是 Proxy，否則是 writer。 |
| `app_reader_endpoint` | 應用程式讀取要連的 host：有 Proxy read-only endpoint 用它；有 Proxy 沒有 read-only 用 Proxy；沒開 Proxy 用 `reader_endpoint`。 |
| `port` | PostgreSQL port（數字，`5432`）。 |
| `master_user_secret_arn` | RDS 管理的 master 帳號 secret 在 Secrets Manager 的 ARN。 |
| `db_identifier` | DB 識別碼：`rds` 是 instance identifier，Aurora 是 cluster identifier。 |
| `identifier_type` | 識別碼型別：`instance` 或 `cluster`。 |
| `cluster_id` | Aurora cluster ID；`rds` 時為 `null`。 |
| `instance_ids` | instance identifier 清單，依序排列，index 0 是 writer。 |
| `cloudwatch_dimension` | 額外告警或 dashboard 用的 dimension，形狀 `{ name, value }`；`name` 是 `DBInstanceIdentifier` 或 `DBClusterIdentifier`。 |
| `arn` | instance（`rds`）或 cluster（Aurora）的 ARN。 |
| `resource_id` | `DbiResourceId`（`rds`）或 `DbClusterResourceId`（Aurora），給 `rds-db:connect` policy 用。 |
| `alarm_arns` | 告警 ARN 的 map，key 是 `<alarm>[_<instance key>]`，例如 `cpu_high_writer`、`connections_high`、`proxy_pinned_high`。 |
| `deployment` | 輸入的 `deployment` 原樣輸出：`rds`、`aurora` 或 `aurora_serverless`。 |
| `database_name` | 輸入的 `database_name` 原樣輸出，也就是隨 instance 或 cluster 建立的資料庫名稱。 |
| `log_group_name` | module 建立的 PostgreSQL CloudWatch log group 名稱：`rds` 是 `/aws/rds/instance/<name>/postgresql`，Aurora 是 `/aws/rds/cluster/<name>/postgresql`（0.2.0 起）。 |
<!-- END_TF_DOCS -->

## `proxy` 欄位

| 欄位 | 預設 | 說明 |
|---|---|---|
| `security_group_ids` | 無（必填） | Proxy 的 security group |
| `role_arn` | `null`（實質必填） | Proxy 的 IAM role ARN，來自 `iam-base` 的 `role_rds_proxy_arn`；宣告成 `optional(string)` 是為了讓 validation 而不是型別轉換擋下缺漏 |
| `require_tls` | `true` | 是否要求 TLS |
| `idle_client_timeout` | `1800` | client 閒置逾時（秒） |
| `max_connections_percent` | `50` | 連線池上限，佔 DB `max_connections` 的百分比 |
| `max_idle_connections_percent` | `25` | 閒置連線上限，佔 DB `max_connections` 的百分比 |
| `debug_logging` | `false` | 是否開 debug log |

## `alarm_config` 欄位

| 欄位 | 預設 | 說明 |
|---|---|---|
| `cpu_threshold` | `80` | CPU 使用率門檻（%） |
| `freeable_memory_bytes` | `209715200` | 可用記憶體下限（bytes） |
| `connections_threshold` | `null` | 連線數門檻。`rds`、`aurora` 必填（`max_connections` 取決於 instance class，離線算不出來）；`aurora_serverless` 沒給時由 `max_capacity` 推算 |
| `replica_lag_threshold_ms` | `1000` | replica lag 門檻（毫秒） |
| `proxy_borrowed_percent` | `80` | Proxy 借出的後端連線佔允許上限的百分比門檻 |
| `proxy_pinned_percent` | `20` | session pinned 連線佔允許上限的百分比門檻 |

## 測試

```bash
scripts/validate.sh modules/rds
```

測試在 plan 階段用 `override_resource { override_during = plan }` 補上 computed 值（端點、`master_user_secret` 這個 nested list、`random_id` 的 hex）；mock 對沒設值的 computed 屬性會填隨機字串，所以「computed 屬性為 null」這類斷言在 mock 下測不了。
