# opensearch-config

設定 OpenSearch domain 裡面的東西：ISM policy（hot → UltraWarm → cold → 刪除）、寫入用的 FGAC role 與 IAM backend role 的 mapping、`ultrawarm_manager`／`cold_manager` 的 mapping、index template。domain 本身用 [`opensearch-domain`](../opensearch-domain/README.md)。

這個 module 用 `opensearch-project/opensearch` provider，**provider 由呼叫端設定**：module 只宣告 `required_providers`，不寫 provider block，帳密不經過 module 的變數。

## 用法

```hcl
# The master credentials are read as an ephemeral value and never reach the state.
ephemeral "aws_secretsmanager_secret_version" "master" {
  secret_id = var.master_user_secret_arn
}

provider "opensearch" {
  url               = "https://${var.opensearch_endpoint}"
  username          = jsondecode(ephemeral.aws_secretsmanager_secret_version.master.secret_string).username
  password          = jsondecode(ephemeral.aws_secretsmanager_secret_version.master.secret_string).password
  sign_aws_requests = false
}

module "search_config" {
  source = "git::https://github.com/<org>/<repo>.git//modules/opensearch-config?ref=opensearch-config-v0.1.0"

  ism_policies = {
    logs = {
      index_patterns  = ["firehose-*"]
      warm_days       = 3
      cold_days       = 7
      delete_days     = 30
      timestamp_field = "@timestamp"
    }
  }

  writer_roles = {
    firehose_writer = {
      index_patterns    = ["firehose-*"]
      backend_role_arns = [var.firehose_role_arn]
    }
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## ISM policy 的行為

`warm_days`、`cold_days`、`delete_days` 都是 index 從建立起算的累計年齡（對應 ISM 的 `min_index_age`），要嚴格遞增。module 產生的狀態依序是：

| 狀態 | action | 何時離開 |
|---|---|---|
| `hot` | 無 | 到 `warm_days` 進 `warm`；沒給 `warm_days` 就到 `delete_days` 進 `delete` |
| `warm`（有 `warm_days`） | `warm_migration`（失敗重試 5 次、間隔 1 小時） | 到 `cold_days` 進 `cold`；沒給 `cold_days` 就到 `delete_days` 進 `delete` |
| `cold`（有 `cold_days`） | `cold_migration`，帶 `timestamp_field` | 到 `delete_days` 進 `delete` |
| `delete` | 經過 cold 的 index 用 `cold_delete`，其他用 `delete` | 終點 |

policy 同時帶 `ism_template`（`index_patterns`、priority 1），新建立的 index 會自動套用。

## 注意

- **cold 一定要 `timestamp_field`。** AWS 文件：ISM 搬到 cold storage 必須明確指定時間欄位，所以有 `cold_days` 就必須有 `warm_days` 與 `timestamp_field`；index 的 mapping 裡要真的有這個欄位（建議用 `index_templates` 定義成 `date`）。
- **要先有 warm 與 cold，再 apply 這個 module。** UltraWarm 啟用後可能要幾小時才能用；domain 還沒開 warm 或 cold 時，搬移會失敗。`ultrawarm_manager`、`cold_manager` 在啟用 warm／cold 的新 domain 上由服務建立，AWS 文件說既有 domain 後來才啟用時可能不存在，要先手動建立；對不存在的 role 做 mapping 會失敗。
- **`writer_roles` 的權限是固定的。** 照 AWS 文件給 Firehose 的那組：cluster `cluster_composite_ops`、`cluster_monitor`；對 `index_patterns` 的 index 有 `create_index`、`manage`、`crud`。`index_patterns` 不能只有 `*`，要限定前綴。VPC 內的 domain 的 role mapping 的 `hosts` 不生效，module 不提供。
- **mapping 是整份取代。** `role_mappings` 對應的 `opensearch_roles_mapping` 會取代該 role 現有的 users 與 backend roles。`all_access`、`security_manager` 不准 mapping（validation 擋下），它們只屬於 master user。
- **provider 與網路。** provider 的 `url` 要連得到 domain endpoint（VPC 內的 runner 或 VPN）；用 master 帳密的 basic auth（`sign_aws_requests = false`），帳密用 ephemeral 資源讀取，不放進變數或 state。每次 plan 與 apply 都會連 domain。
- 這個 module 只做過離線的靜態驗證（provider 是 mock），沒有連過任何 OpenSearch。

## 刻意不做

`opensearch_user`（密碼也會進 state；人員帳號由 master 在 Dashboards 建）、snapshot repository、Dashboards saved object、自訂 action group、provider block。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `ism_policies` | `map(object)` | `{}` | 否 | ISM policy，key 是 policy id。`index_patterns` 是新 index 自動套用這份 policy 的樣式；`warm_days`、`cold_days`、`delete_days` 是 index 年齡（天，從建立算起、累計）：到 `warm_days` 搬進 UltraWarm、到 `cold_days` 搬進 cold、到 `delete_days` 刪除，三個要嚴格遞增。沒給 `warm_days` 就沒有 warm 階段（hot 直接到刪除）。有 `cold_days` 就必須有 `warm_days` 與 `timestamp_field`（搬到 cold 一定要指定時間欄位）。 |
| `writer_roles` | `map(object)` | `{}` | 否 | 寫入用的 FGAC role，key 是 role 名稱。權限固定是 AWS 文件給 Firehose 的那組：cluster `cluster_composite_ops`、`cluster_monitor`；對 `index_patterns` 的 index 有 `create_index`、`manage`、`crud`。`backend_role_arns` 是對應的 IAM role ARN（例如 Firehose 的 role），至少一個。`index_patterns` 不能只有 `*`，要限定 index 前綴。 |
| `role_mappings` | `map(object)` | `{}` | 否 | 內建 role 的 mapping，key 是 role 名稱，例如 `ultrawarm_manager`、`cold_manager`。`users` 是 internal user 名稱，`backend_role_arns` 是 IAM role ARN，至少給一種。這個資源會取代 role 現有的整份 mapping。不准 mapping `all_access`、`security_manager`，也不能跟 `writer_roles` 的名稱重複。 |
| `index_templates` | `map(object)` | `{}` | 否 | composable index template，key 是 template 名稱。`mappings` 是 JSON 字串（例如把 ISM 要用的 `timestamp_field` 定義成 `date`），不給就不設 mappings。`priority` 預設 100。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `ism_policy_ids` | ISM policy id，依 key 排序。 |
| `writer_role_names` | 寫入用 FGAC role 的名稱，依 key 排序。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/opensearch-config
```
