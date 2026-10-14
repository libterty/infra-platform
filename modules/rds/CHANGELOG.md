# Changelog

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
