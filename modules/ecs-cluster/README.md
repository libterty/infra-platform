# ecs-cluster

建一個 Fargate 用的 ECS cluster：Container Insights、FARGATE 與 FARGATE_SPOT capacity provider、預建的 performance log group，可選 Service Connect namespace。

## 用法

```hcl
module "cluster" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ecs-cluster?ref=ecs-cluster-v0.1.0"

  name                      = "alpha-dev"
  service_connect_namespace = "alpha-dev.local"

  tags = {
    Project = "alpha"
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。`ecs-service` 的 `cluster_arn` 傳 `module.cluster.cluster_arn`。

## 注意

- FARGATE 與 FARGATE_SPOT 一律都掛上；`default_capacity_provider_strategy` 只決定沒指定策略的 service 用哪個，預設只有 FARGATE。
- `container_insights` 不是 `disabled` 時，module 會預建 `/aws/ecs/containerinsights/<name>/performance` log group 並設保留天數。不預建的話 AWS 首次寫入指標時會自動建立，且永不過期。
- 已經有 cluster 的帳號導入時，performance log group 可能已被 AWS 自動建立，apply 會因名稱重複失敗，要先 import。

## 刻意不做

- 不建 execution role，也不建任何 IAM 資源。role 在範本的 `iam-base` stack 建。
- 不支援 EC2 capacity provider。
- 不設 ECS Exec 的 cluster 層 logging。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | cluster 名稱，2–63 字元，小寫英數字與連字號，字母開頭 |
| `container_insights` | `string` | `"enhanced"` | 否 | `disabled`、`enabled`、`enhanced` |
| `default_capacity_provider_strategy` | `list(object)` | `[{ capacity_provider = "FARGATE" }]` | 否 | 只能是 FARGATE、FARGATE_SPOT；最多一個 `base > 0` |
| `service_connect_namespace` | `string` | `null` | 否 | Cloud Map HTTP namespace 名稱；`null` 不建 |
| `log_retention_days` | `number` | `30` | 否 | performance log group 保留天數，必須是 CloudWatch Logs 接受的值 |
| `log_kms_key_arn` | `string` | `null` | 否 | performance log group 的 KMS key |
| `tags` | `map(string)` | `{}` | 否 | 每個資源的 tag；`Name` 由 module 加上 |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `cluster_name` | `string` | cluster 名稱 |
| `cluster_arn` | `string` | cluster ARN |
| `cluster_id` | `string` | cluster id |
| `service_connect_namespace_arn` | `string` | namespace ARN；沒建時為 `null` |

## 測試

```bash
scripts/validate.sh modules/ecs-cluster
```
