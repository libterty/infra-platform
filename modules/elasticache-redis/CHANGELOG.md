# Changelog

## 0.1.0（2026-10-20）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立 cluster mode enabled 的 Redis replication group，加上 subnet group 與 parameter group。
- parameter group 的 family 由 `engine_version` 的主版本推得：7.x 為 `redis7`，6.x 為 `redis6.x`。`cluster-enabled = yes` 固定，`parameters` 不能覆寫它。
- 固定且沒有開關：at-rest 與 transit 加密、automatic failover、multi-AZ；`replicas_per_node_group` 至少 1，`subnet_ids` 至少 2 個。
- 預先建立 slow log 與 engine log 兩個 log group（`/aws/elasticache/<name>/slow-log`、`/engine-log`），log delivery 以 JSON 格式送過去。`kms_key_arn` 同時用在 at-rest 加密與兩個 log group。
- 可選 `autoscaling`：對 shard 數建 `aws_appautoscaling_target` 與 CPU target tracking policy（預設 70%）；`cache.t*` 不能搭配。
- 告警：每個 member 一條 `DatabaseMemoryUsagePercentage`（預設 80%）；有給 `evictions_threshold` 才建 evictions 告警。`sns_topic_arns` 必填。
- member id 依 `<name>-<shard 4 位>-<node 3 位>` 推導，並用 precondition 與 AWS 回報的 `member_clusters` 核對。
- 輸出 `configuration_endpoint`、`port`、`replication_group_id`、`member_clusters`、`arn`、`log_group_names`、`alarm_arns`。
- 已知限制：`num_node_groups` 固定 `ignore_changes`，建好後改它不會生效；不設 AUTH token，只靠 TLS 與 security group；只支援 Redis 6、7，不支援 Valkey、Global Datastore、自訂 snapshot 時間、user group／RBAC。
