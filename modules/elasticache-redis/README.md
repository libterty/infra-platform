# elasticache-redis

建一個 cluster mode enabled 的 ElastiCache Redis replication group，包含 subnet group、parameter group、slow log 與 engine log 的 log group、可選的 shard autoscaling，以及 memory／evictions 告警。給 rate limit、串流狀態這類需要共享快取的服務用。

## 用法

```hcl
module "redis" {
  source = "git::https://github.com/<org>/<repo>.git//modules/elasticache-redis?ref=elasticache-redis-v0.1.0"

  name           = "alpha-dev-rate-limit"
  engine_version = "7.1"
  node_type      = "cache.r7g.large"

  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.redis_sg.security_group_id]

  sns_topic_arns = [module.alarm_topic.topic_arn]

  tags = {
    Project = "alpha"
  }
}
```

完整範例（含 autoscaling 與 evictions 告警）見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定的設定

下面這些沒有開關，也不能用輸入關掉：

- at-rest 加密與 transit（TLS）加密。
- automatic failover 與 multi-AZ。所以 `replicas_per_node_group` 至少 1，`subnet_ids` 至少 2 個。
- `cluster-enabled = yes`。`parameters` 裡設 `cluster-enabled`（不分大小寫）會被拒絕。

## 注意

- **建好之後改 `num_node_groups` 不會生效。** 這個欄位固定 `ignore_changes`，讓 autoscaling 調整 shard 數時 plan 不會想把它改回去。要改 shard 數，請用 `autoscaling` 或自己重建。autoscaling 改變 shard 數之後，下面的 member 告警會跟實際不符（新增的 shard 沒有告警、縮掉的 shard 的告警會變成沒有資料）。
- **沒有 AUTH token。** 存取控制只靠 TLS 加 security group。這是已知的安全取捨：只要能連到 port 的來源就能下指令，所以 security group 只開給需要的 client。
- 連線要用支援 cluster mode 的 Redis client，並開啟 TLS，連到 `configuration_endpoint`。
- parameter group family 由 `engine_version` 主版本推得：`7.x` 為 `redis7`，`6.x` 為 `redis6.x`。只收主版本 6 與 7。換主版本會讓 parameter group 換 family，請先確認可以替換。
- `kms_key_arn` 同時加密 replication group 與兩個 log group。key policy 要允許 `logs.<region>.amazonaws.com`，也要允許 ElastiCache 使用。
- `cache.t*` 不能搭配 `autoscaling`（validation 會拒絕）。`autoscaling` 要求 `num_node_groups` 落在 `min_shards`～`max_shards` 之間。
- log group 在 replication group 之前建立，保留天數（預設 30，不接受 0）與 KMS 由這個 module 決定。

## 告警

- 每個 member cluster 一條 memory 告警：`DatabaseMemoryUsagePercentage` 大於等於 `alarm_config.memory_percent`（預設 80），連續 3 個 5 分鐘。
- `alarm_config.evictions_threshold` 有給才建 evictions 告警，每個 member 一條，5 分鐘內 `Evictions` 總和大於等於門檻，3 期中 2 期達標。沒給就不建。
- 告警與 OK 都送到 `sns_topic_arns`。`sns_topic_arns` 必填。
- member id 依 AWS 的命名規則推導：`<name>-<shard，4 位數>-<node，3 位數>`，例如 `alpha-dev-rate-limit-0001-001`。shard 數量是 `num_node_groups`，每個 shard 的 node 數是 `replicas_per_node_group + 1`。
- **這個命名規則是推論，沒有在真實 AWS 驗證過**（測試用 mock provider）。所以每條 memory 告警有 precondition：沒設 `autoscaling` 時，推導出的 id 集合必須等於 AWS 回報的 `member_clusters`，不一致就 apply 失敗；有 `autoscaling` 時 shard 數會自己變動，只要求推導的 id 與實際 member 有交集。第一次 apply 如果在這裡失敗，表示實際命名規則跟推論不同，請回報。
- 因為上面的 precondition，沒設 `autoscaling` 時改 `num_node_groups` 會直接 apply 失敗（而不是默默沒有效果）。

## 刻意不做

- 關閉加密、failover、multi-AZ 的開關。
- AUTH token、user group／RBAC。
- Valkey、Memcached、cluster mode disabled、Global Datastore。
- 建 security group 與 IAM；請用 `security-group` 建好再傳進來。
- scheduled scaling 與自訂 step scaling。
- WAF、備份到 S3 的 snapshot 匯出、自訂 maintenance／snapshot 時間窗。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | replication group ID，也用來命名 subnet group、參數群組與 log group。1–40 字元，限小寫英數與連字號，字母開頭，不可連續連字號或以連字號結尾。 |
| `description` | `string` | `null` | 否 | replication group 的說明；`null` 時自動產生。 |
| `engine_version` | `string` | 無 | 是 | Redis 引擎版本，主版本 6 或 7，例如 `7.1`、`7.0`、`6.2`、`6.x`。參數群組 family 由主版本推得。 |
| `node_type` | `string` | 無 | 是 | 節點類型，例如 `cache.r7g.large`。`cache.t*` 不能搭配 `autoscaling`。 |
| `port` | `number` | `6379` | 否 | cluster 監聽的 port，1–65535。 |
| `subnet_ids` | `list(string)` | 無 | 是 | subnet group 用的 subnet，至少 2 個、分屬不同 AZ（multi-AZ 一律開啟）。 |
| `security_group_ids` | `list(string)` | 無 | 是 | 掛在 cluster 上的 security group，至少 1 個。存取控制靠這些 security group 與 TLS，沒有 AUTH token。 |
| `num_node_groups` | `number` | `1` | 否 | 初始 shard 數，1–500。建好後會被忽略（shard 數交給 autoscaling），之後改它不會生效。 |
| `replicas_per_node_group` | `number` | `1` | 否 | 每個 shard 的 replica 數，1–5。至少 1 個，因為 automatic failover 與 multi-AZ 一律開啟。 |
| `parameters` | `map(string)` | `{}` | 否 | 參數群組的額外參數。`cluster-enabled` 固定為 `yes`，不能在這裡設定。 |
| `snapshot_retention_limit` | `number` | `0` | 否 | 自動 snapshot 保留天數，0–35；`0` 時不做 snapshot。 |
| `apply_immediately` | `bool` | `false` | 否 | 是否立即套用修改；`false` 時等下一個維護時段。 |
| `kms_key_arn` | `string` | `null` | 否 | at-rest 加密與兩個 log group 用的 customer managed key，key policy 必須允許 `logs.<region>.amazonaws.com`。`null` 時用 AWS managed key。 |
| `log_retention_days` | `number` | `30` | 否 | slow log 與 engine log 兩個 log group 的保留天數，限 CloudWatch Logs 接受的值（1、3、5、7、14、30、60、90 … 3653），不接受 `0`（永久保留）。 |
| `autoscaling` | `object` | `null` | 否 | 依 primary 引擎 CPU 自動調整 shard 數；`null` 時不開，`cache.t*` 不能用。欄位：`min_shards`、`max_shards`（必填，`1 <= min_shards <= max_shards <= 500`，且 `num_node_groups` 要落在這個範圍內）、`target_cpu`（預設 `70`，大於 0、最多 100）。 |
| `alarm_config` | `object` | `{}` | 否 | 告警門檻。欄位：`memory_percent`（預設 `80`，大於 0、最多 100，套用到每個 member 的 `DatabaseMemoryUsagePercentage`）、`evictions_threshold`（預設 `null`，有給才建 evictions 告警，必須大於 0）。 |
| `sns_topic_arns` | `list(string)` | 無 | 是 | 告警與恢復 OK 時通知的 SNS topic ARN，至少 1 個。 |
| `tags` | `map(string)` | `{}` | 否 | 每個資源的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `configuration_endpoint` | cluster mode 的 configuration endpoint。client 必須用支援 cluster mode 的 Redis client 並開 TLS。 |
| `port` | cluster 監聽的 port（數字）。 |
| `replication_group_id` | replication group ID。 |
| `member_clusters` | AWS 回報的 member cluster ID 清單，已排序。 |
| `arn` | replication group ARN。 |
| `log_group_names` | log group 名稱的 map，key 是 `slow_log`、`engine_log`。 |
| `alarm_arns` | 告警名稱對 ARN 的 map，包含每個 member 的 memory 告警與（有設門檻時的）evictions 告警。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/elasticache-redis
```
