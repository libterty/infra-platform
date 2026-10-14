# Changelog

## 0.1.0（未發布）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立 `aws_ecs_cluster`，Container Insights 預設 `enhanced`。
- 掛上 FARGATE 與 FARGATE_SPOT，預設策略由 `default_capacity_provider_strategy` 決定（預設只有 FARGATE）。
- `container_insights` 不是 `disabled` 時預建 performance log group，可設保留天數與 KMS key。
- `service_connect_namespace` 有值時建立 Cloud Map HTTP namespace。
- 輸出 `cluster_name`、`cluster_arn`、`cluster_id`、`service_connect_namespace_arn`。
- 不建 IAM、不支援 EC2 capacity provider。
