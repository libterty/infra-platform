# Changelog

## 0.1.1（未發布）

新增功能，照 semver 表本該升 MINOR；這一版照使用者決定（design 決策 54）跟 7 個新 module 一起用 `0.1.1`，在增補驗收後手動打 tag（manifest 屆時才改成 `0.1.1`），release-please 不會產生這一段。之後的版本照 semver 表。

- 新變數 `data_api`（預設 `false`）：在 Aurora cluster 開 RDS Data API（`enable_http_endpoint`），給 Bedrock Knowledge Base 的 Aurora 向量儲存用；`deployment = "rds"` 配 `true` 會被 validation 擋下。既有消費端換版、不改程式碼時 plan 應零差異：`enable_http_endpoint` 在 schema 是 optional、非 computed，沒設時 provider 當成 `false`，現在明寫 `false`。**這是讀 schema 推論的，沒有用 plan 驗證。**
- 新輸出 `deployment`、`database_name`：輸入值原樣輸出（design D21 的待辦），讓呼叫端發布資料庫資訊時不用再從自己的變數取。

## 0.1.0（未發布）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- `deployment` 三選一：`rds`（一般 RDS PostgreSQL）、`aurora`（provisioned cluster）、`aurora_serverless`（Serverless v2）。選了哪個型態就必須給對應物件（`rds`／`aurora`／`serverless`），另外兩個必須是 null。
- 可選 RDS Proxy（`proxy != null`）：`SECRETS` 認證、IAM 認證關閉；Aurora 且有 reader 時另建 read-only endpoint。
- 密碼由 RDS 管理（`manage_master_user_password = true`），module 沒有任何 password 變數。
- 預設參數：`log_min_duration_statement = 500`、`log_lock_waits = 1`、`rds.force_ssl = 1`、`shared_preload_libraries = pg_stat_statements`，呼叫端同名參數覆蓋。
- 一律加密、不公開、開 Performance Insights、export `postgresql` log（log group 預先建立）。
- final snapshot 名稱 `<name>-final-<random_id>`。
- 告警：`cpu_high`、`freeable_memory_low`（每個 instance）、`connections_high`、`replica_lag_high`（Aurora 有 reader）、`proxy_borrowed_high`、`proxy_pinned_high`（有 Proxy）。`sns_topic_arns` 必填。
- 輸出在三種型態下格式一致：`writer_endpoint`、`reader_endpoint`、`app_endpoint`、`app_reader_endpoint`、`has_reader`、`identifier_type`、`cloudwatch_dimension` 等。
- 不建任何 IAM（Proxy 與 Enhanced Monitoring 的 role 由呼叫端傳入）；不做 read replica、Multi-AZ DB cluster、MySQL。
