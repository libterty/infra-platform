# opensearch-domain

建一個 VPC 內的 OpenSearch managed domain：hot data 節點，可選 dedicated master、UltraWarm 與 cold storage，log 送 CloudWatch Logs。加密、HTTPS、TLS 1.2 PFS、fine-grained access control（FGAC）都是固定值，不是輸入。master user 的帳密從 Secrets Manager 的 secret 讀，module 沒有任何密碼變數。

## 用法

```hcl
module "search" {
  source = "git::https://github.com/<org>/<repo>.git//modules/opensearch-domain?ref=opensearch-domain-v0.1.0"

  name           = "alpha-dev-search"
  engine_version = "OpenSearch_2.19"

  hot = {
    instance_type  = "m7g.large.search"
    instance_count = 2
    ebs            = { volume_size = 20 }
  }
  dedicated_master = { instance_type = "m7g.large.search", count = 3 }
  warm             = { instance_type = "ultrawarm1.medium.search", count = 2 }
  cold_storage     = true

  subnet_ids         = module.vpc.subnet_ids_data
  security_group_ids = [module.sg.id]

  kms_key_arn            = module.key.key_arn
  master_user_secret_arn = aws_secretsmanager_secret.opensearch_master.arn
  access_principal_arns  = [module.firehose_role.arn]
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。domain 裡面的設定（ISM、FGAC role 與 mapping）用 [`opensearch-config`](../opensearch-config/README.md)。

## 固定行為

| 項目 | 值 |
|---|---|
| 位置 | 一律在 VPC 內（`vpc_options`），沒有 public 選項 |
| 靜態加密 | `encrypt_at_rest` 開，key 是必填輸入 `kms_key_arn` |
| 傳輸加密 | `node_to_node_encryption` 開；`enforce_https = true`、`tls_security_policy = "Policy-Min-TLS-1-2-PFS-2023-10"` |
| 存取控制 | FGAC 開、`internal_user_database_enabled = true`、`anonymous_auth_enabled = false` |
| master user | 帳密來自 `master_user_secret_arn` 的 JSON（`username`、`password`） |
| AZ | `zone_awareness_enabled = true`，`availability_zone_count` 預設 2 |
| log | 每種 log 類型一個 log group（CMK、`log_retention_days`），加一份讓 `es.amazonaws.com` 寫入的 resource policy |
| tag | 給定的 `tags` 加上 `Name` |

## 注意

- **安全例外：master 帳密會進 state。** `aws_opensearch_domain` 的 `master_user_password` 沒有 write-only 版本，所以密碼以明文留在呼叫端 stack 的 state，共兩份：domain 屬性一份，這個 module 讀 secret 的 data source 一份（plan 輸出標 sensitive）。讀得到 state 的人等於拿到 `all_access` 與 `security_manager`。補償控制：module 沒有密碼變數（`scripts/validate.sh` 的 S7 擋住）、state bucket 要用專用 CMK 並限制讀取與縮短舊版本保留、domain 的 SG 只放 VPN 與 VPC 內的 runner、master 不給日常使用（人員帳號由 master 在 Dashboards 建）、`AUDIT_LOGS` 開並用 CMK、secret 只給 deploy role 與 break-glass role 讀。移除這個例外的時機：aws provider 出現 `master_user_password_wo` 時改用 ephemeral 讀 secret，或組織有 IdP 時改接 SAML 並把 master 換成 IAM role。完整記錄見 [`docs/design/v7/design-docs.md`](../../docs/design/v7/design-docs.md) §4.1。
- **master secret 的格式與密碼規則。** secret 的值是 JSON：`{"username": "...", "password": "..."}`，secret 在 Terraform 外建立並寫值（例如 `aws secretsmanager get-random-password` 產生後 `put-secret-value`）。AWS API 對 `MasterUserPassword` 的限制是長度 8–128 字元（pattern `.*`）；module 在 plan 時檢查 secret 是 JSON、`username` 非空、密碼 8–128 字元。AWS 文件沒有在 API 參考列出字元類別規則，建議密碼含大寫、小寫、數字與符號，避開 `"`、`\` 與空白；服務端若有額外規則要等 apply 才看得到（尚未在真實帳號驗證）。
- **basic auth 不經過 access policy。** `access_principal_arns` 只管 SigV4 簽章的請求（例如 Firehose 的 role）；用帳密登入的請求（Dashboards、`curl -u`）只受 FGAC 與網路控制。`access_principal_arns` 不收 `*` 與萬用字元，也不收 `root`；空的就不設 access policy。policy 的 Action 是 `es:ESHttp*`，實際能做什麼由 FGAC 的 role mapping 決定。
- **log resource policy 是必要的。** AWS 文件要求先有 CloudWatch Logs resource policy，讓 `es.amazonaws.com` 對 log group 有 `logs:CreateLogStream`、`logs:PutLogEvents`，建立或更新 domain 時才能開 log publishing。module 用帳號層的 policy（`aws_cloudwatch_log_resource_policy` 的 `policy_name` 寫法，AWS 文件的做法），一個 domain 一份，Resource 列這個 module 的 log group，並帶 `aws:SourceAccount` 與 `aws:SourceArn`（這個 domain）。CloudWatch Logs 每個 Region 最多 10 份 resource policy，同一個帳號同一個 Region 放很多 domain 會撞到上限。掛在 log group 上的 `resource_arn` 寫法（aws provider 6.36 起）能不能給 OpenSearch 用，沒有文件，沒有採用。
- **log group 的 CMK。** `kms_key_arn` 同時用來加密 log group，key policy 要允許 `logs.<region>.amazonaws.com`；`AUDIT_LOGS` 要另外在 Dashboards（或 `opensearch_audit_config`）開啟稽核設定才會有內容。至少要選一種 log 類型，沒有「不開 log」的選項。
- **UltraWarm 與 cold 的條件。** `warm` 要有 `dedicated_master`、hot 不能是 T2／T3、`multi_az_with_standby` 開啟時 `warm.count` 要是 `availability_zone_count` 的倍數（`terraform plan` 就擋）。cold 要同時有 `warm`，cold 要 OpenSearch 或 Elasticsearch 7.9 以上。warm 的最小台數、T3 master 能不能搭 UltraWarm，AWS 文件沒寫，module 不檢查，要在真實帳號驗證。啟用後 UltraWarm 可能要幾小時才能用，warm index 唯讀；停用 warm 或 cold 前要先刪除或搬回所有 index。
- **warm 與 cold 的 FGAC role。** `ultrawarm_manager`、`cold_manager` 在啟用 warm／cold 的新 domain 上由服務建立；AWS 文件說既有 domain 後來才啟用時可能沒有，要手動建立。
- **版本。** `engine_version` 只收 `OpenSearch_<主>.<次>`，UltraWarm 與 cold 從 2.17 起可用於 KNN index；2025-05 起服務支援 OpenSearch 2.19，之後也支援 3.x，實際可用版本以 AWS 文件為準。
- **instance type 與台數。** `.search` 結尾由 module 檢查，具體型號 aws provider 與 tflint 都不檢查，打錯要等 apply 才失敗。AWS 規定 dedicated master 的 `count` 要大於 2 且不是 4，`hot.instance_count` 要大於 1；`hot.instance_count` 不能少於 `availability_zone_count`，`subnet_ids` 的數量要等於 `availability_zone_count`。
- **權限。** 第一次建立 domain 時，apply 的身分要有 `iam:CreateServiceLinkedRole`（OpenSearch 的 service-linked role）與讀 master secret 的 `secretsmanager:GetSecretValue`（secret 用 CMK 時還要 `kms:Decrypt`）。這個 module 不建 IAM 與 SG。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

public domain、IAM master user、Cognito、SAML、custom endpoint、cross-cluster、package、OpenSearch Serverless、ISM（用 `opensearch-config`）、自己產生密碼、密碼輸入變數。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | domain 名稱：3–28 字元，小寫英文字母開頭，只含小寫英文字母、數字與 `-`。同一個帳號同一個 region 內不可重複。 |
| `engine_version` | `string` | 無 | 是 | 引擎版本，格式 `OpenSearch_<主版號>.<次版號>`，例如 `OpenSearch_2.19`。UltraWarm 與 cold storage 需要 OpenSearch 或 Elasticsearch 7.9 以上；module 只收 OpenSearch。 |
| `hot` | `object` | 無 | 是 | hot（data）節點：`instance_type`（`.search` 結尾）、`instance_count`（至少 2，且不少於 `availability_zone_count`）、`ebs`（`volume_size` 單位 GiB；`volume_type` 預設 `gp3`，可選 `gp2`、`io1`；`iops`、`throughput` 選填）。啟用 `warm` 時不能用 T2／T3。 |
| `dedicated_master` | `object` | `null` | 否 | dedicated master 節點：`instance_type`（`.search` 結尾）、`count`（3，或 5 以上；不能是 2、4）。`null` 表示不用 dedicated master；啟用 `warm` 時必填。 |
| `warm` | `object` | `null` | 否 | UltraWarm 節點：`instance_type`（`ultrawarm1.medium.search`、`ultrawarm1.large.search`、`ultrawarm1.xlarge.search`）、`count`（至少 1）。`null` 表示不用。要有 `dedicated_master`，hot 不能是 T2／T3，`multi_az_with_standby` 開啟時 `count` 要是 `availability_zone_count` 的倍數。 |
| `cold_storage` | `bool` | `false` | 否 | 是否啟用 cold storage。必須同時有 `warm`。停用前要先刪除或搬回所有 cold index。 |
| `availability_zone_count` | `number` | `2` | 否 | 使用的 AZ 數，2 或 3。`subnet_ids` 的數量要跟它相同。 |
| `multi_az_with_standby` | `bool` | `false` | 否 | 是否啟用 Multi-AZ with Standby。開啟時 `warm.count` 要是 `availability_zone_count` 的倍數，AWS 也要求 dedicated master 與 3 個 AZ 的資料節點配置（module 只檢查文件明寫的倍數條件）。 |
| `subnet_ids` | `list(string)` | 無 | 是 | domain 所在的 subnet ID，每個 AZ 一個，數量要等於 `availability_zone_count`。domain 一律在 VPC 內，沒有 public 選項。 |
| `security_group_ids` | `list(string)` | 無 | 是 | domain 的 security group ID，至少一個。SG 由呼叫端用 `security-group` module 建，這個 module 不建 SG。 |
| `kms_key_arn` | `string` | 無 | 是 | domain 靜態加密與 log group 加密用的客戶管理 KMS key ARN，必填。key policy 要讓 OpenSearch 與 CloudWatch Logs 能用這把 key。 |
| `master_user_secret_arn` | `string` | 無 | 是 | master user 帳密所在的 Secrets Manager secret ARN；secret 的值是 JSON `{"username": "...", "password": "..."}`。module 用 data source 讀取，沒有密碼變數。密碼會因此留在 state（見 README〈注意〉）。 |
| `access_principal_arns` | `list(string)` | `[]` | 否 | domain access policy 允許的 IAM role 或 user ARN（用 SigV4 簽章的呼叫端，例如 Firehose 的 role）。不收 `*` 與萬用字元；空的表示不設 access policy。HTTP basic auth 不經過這份 policy，只受 FGAC 控制。 |
| `log_types` | `set(string)` | `[ "ES_APPLICATION_LOGS", "AUDIT_LOGS" ]` | 否 | 要送到 CloudWatch Logs 的 log 類型（`ES_APPLICATION_LOGS`、`AUDIT_LOGS`、`SEARCH_SLOW_LOGS`、`INDEX_SLOW_LOGS`），每種一個 log group，至少一種。`AUDIT_LOGS` 還要在 Dashboards 開啟稽核設定才會有內容。 |
| `log_retention_days` | `number` | `30` | 否 | log group 的保留天數，必須是 CloudWatch Logs 支援的值（1、3、5、7、14、30、60、90、120、150、180、365、400、545、731、1096、1827、2192、2557、2922、3288、3653）。 |
| `auto_tune` | `bool` | `false` | 否 | 是否啟用 Auto-Tune。T2／T3 等小型 instance 不支援。 |
| `off_peak_window_start` | `number` | `null` | 否 | off-peak window 的起始小時（UTC，0–23），window 長 10 小時。`null` 表示不設定，沿用服務預設。 |
| `automated_snapshot_start_hour` | `number` | `null` | 否 | 自動快照的起始小時（UTC，0–23）。`null` 表示不設定；OpenSearch 5.3 以上的 domain 每小時自動快照，這個值會被服務忽略。 |
| `tags` | `map(string)` | `{}` | 否 | 資源的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `domain_arn` | domain 的 ARN。 |
| `domain_name` | domain 名稱。 |
| `endpoint` | domain 的 VPC endpoint（不含 `https://`）。只有 VPC 內與 VPN 連得到。 |
| `dashboard_endpoint` | OpenSearch Dashboards 的 endpoint（含 `/_dashboards` 路徑，不含 `https://`）。 |
| `log_group_arns` | log group 的 ARN，key 是 log 類型（例如 `AUDIT_LOGS`）。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/opensearch-domain
```
