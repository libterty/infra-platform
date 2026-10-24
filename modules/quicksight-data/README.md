# quicksight-data

建 QuickSight（文件已改名 Amazon Quick Sight，API 與 provider 仍叫 `quicksight`）的資料層：Athena data source、Redshift data source、連進 VPC 的 VPC connection、dataset，以及這些資源的 user／group 權限。BI 的資料入口，不管 QuickSight 帳號本身。

## 用法

```hcl
module "bi" {
  source = "git::https://github.com/<org>/<repo>.git//modules/quicksight-data?ref=quicksight-data-v0.1.0"

  aws_account_id = "111111111111"

  athena_sources = {
    alpha-dev-athena = {
      workgroup = module.athena.workgroup_name
      role_arn  = module.role_quicksight_athena.arn
    }
  }

  # Optional: leave empty to create the Athena source only.
  redshift_sources = {
    alpha-dev-redshift = {
      host       = module.warehouse.endpoint_address
      database   = module.warehouse.database_name
      secret_arn = var.quicksight_redshift_secret_arn
    }
  }

  vpc_connection = {
    name               = "alpha-dev-redshift"
    role_arn           = module.role_quicksight_vpc.arn
    subnet_ids         = module.vpc.subnet_ids_data
    security_group_ids = [module.sg_quicksight.id]
  }

  datasets = {
    alpha-dev-events = {
      source_key = "alpha-dev-athena"
      sql        = "SELECT event_id, event_time FROM \"alpha_dev_curated\".\"events\""
      columns = [
        { name = "event_id", type = "STRING" },
        { name = "event_time", type = "DATETIME" },
      ]
    }
  }

  owner_principals  = ["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/alpha-dev-bi-owners"]
  reader_principals = ["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/alpha-dev-bi-readers"]
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| Athena 來源 | `type = "ATHENA"`，用給定的 `workgroup` 與專用的 `role_arn`（覆蓋帳號層預設 role） |
| Redshift 來源 | `type = "REDSHIFT"`，驗證只用 `credentials.secret_arn`；沒有帳密輸入，也不借用其他 data source 的憑證 |
| Redshift 的 SSL | `ssl_properties.disable_ssl = false`，沒有關閉的選項 |
| Redshift 的網路 | 一律經 `vpc_connection_properties` 連到 module 建的 VPC connection；有 Redshift 來源卻沒給 `vpc_connection` 會被 validation 擋下 |
| 沒給 Redshift 來源 | `redshift_sources` 是空 map 就一個 Redshift data source 都不建（呼叫端沒有 secret 時傳 `{}`） |
| VPC connection | 給了 `vpc_connection` 才建，即使還沒有 Redshift 來源 |
| dataset | 每個 dataset 一張 physical table（`sql` 的自訂 SQL 或 `table` 的 relational table），加一張同名的 logical table；`import_mode` 預設 `DIRECT_QUERY` |
| 擁有者權限 | `owner_principals` 對每個 data source 取得 6 個 action、對每個 dataset 取得 10 個 action |
| 唯讀權限 | `reader_principals` 對每個 data source 取得 3 個 action、對每個 dataset 取得 5 個 action |
| 命名 | map 的 key 同時是 data source、dataset 的 ID 與名稱；VPC connection 的 `name` 同時是 ID 與名稱 |

權限的 action 清單：

| 對象 | 擁有者 | 唯讀 |
|---|---|---|
| data source | `quicksight:DescribeDataSource`、`DescribeDataSourcePermissions`、`PassDataSource`、`UpdateDataSource`、`DeleteDataSource`、`UpdateDataSourcePermissions` | `quicksight:DescribeDataSource`、`DescribeDataSourcePermissions`、`PassDataSource` |
| dataset | `quicksight:DescribeDataSet`、`DescribeDataSetPermissions`、`PassDataSet`、`DescribeIngestion`、`ListIngestions`、`UpdateDataSet`、`DeleteDataSet`、`CreateIngestion`、`CancelIngestion`、`UpdateDataSetPermissions` | `quicksight:DescribeDataSet`、`DescribeDataSetPermissions`、`PassDataSet`、`DescribeIngestion`、`ListIngestions` |

principal 只收 QuickSight 的 user 或 group ARN（`arn:aws:quicksight:<identity region>:<account>:user/<namespace>/<name>` 或 `group/<namespace>/<name>`）。`<identity region>` 是 QuickSight 帳號的 identity region，不一定是這個 module 部署的 region。同一個 principal 不能同時在兩個清單。兩個清單都是空的，data source 與 dataset 就沒有任何人能在 QuickSight 裡看到。

## 前置作業

1. **QuickSight 帳號要先訂閱**，VPC connection 需要 Enterprise 版。這個 module 不管 `aws_quicksight_account_subscription`、user、group、namespace，那些在 module 外建立，ARN 傳給 `owner_principals`、`reader_principals`。
2. **Redshift 用的 secret 在 repo 外建立**，內容至少要有 `username`、`password`（其他欄位 QuickSight 會忽略）。DB user 用專用的唯讀帳號，不用 admin。
3. **QuickSight 管理者要在主控台授權這個 secret**：Manage Quick → Security & permissions → Quick access to AWS resources → AWS Secrets Manager → Select secrets。授權後 QuickSight 會建 `aws-quicksight-secretsmanager-role-v0`，使用者看 dashboard 時用這個 role 讀 secret。secret 若用客戶管理的 KMS key 加密，這個 role 要有那把 key 的 `kms:Decrypt`。這一步不能用 Terraform 做。
4. **執行 Terraform 的身分要能讀這個 secret**（`secretsmanager:GetSecretValue`，key 加密時再加 `kms:Decrypt`）：AWS 文件寫，建立或更新用 secret 的 data source 時，QuickSight 是依 API 呼叫者自己的 IAM policy 授權讀取 secret，不是依上面那個 service role。
5. **Redshift 來源要有 VPC connection 的 role 與 security group**：role 信任 `quicksight.amazonaws.com`，權限是 `ec2:CreateNetworkInterface`、`ec2:ModifyNetworkInterfaceAttribute`、`ec2:DeleteNetworkInterface`、`ec2:DescribeSubnets`、`ec2:DescribeSecurityGroups`；security group 的對象 Redshift 那一側要放行 QuickSight 的 security group 連到 Redshift 的 port。
6. **Athena 來源的 role**：信任 `quicksight.amazonaws.com`；權限限於該 workgroup 的查詢、資料與查詢結果 bucket 的讀寫、Glue catalog 讀取與用到的 KMS key。
7. 部署者要有對 `athena_sources.role_arn` 與 `vpc_connection.role_arn` 的 `iam:PassRole`，以及建立與更新 data source、dataset、VPC connection 和它們權限的 `quicksight:` action。

## 注意

- **Redshift 為什麼只能用 secret**：provider 的 `parameters.redshift` 只有 `cluster_id`、`host`、`port`、`database`，沒有 IAM 參數，驗證只剩 `credentials.secret_arn` 與帳密兩種。帳密那種寫法會讓密碼進 Terraform state，所以這個 module 沒有收。（AWS 的 `RedshiftParameters` API 另有 `IAMParameters`，但 provider 6.70 沒有對應欄位。）
- `redshift_sources.host` 用 Redshift 端點的 DNS 名稱（Serverless 是 workgroup endpoint，provisioned 是 cluster endpoint），port 預設 5439。這個 module 不設 `cluster_id`。
- `vpc_connection.subnet_ids` 至少 2 個、最多 15 個（provider 的限制），建議放在不同 AZ，module 驗不了這點。`dns_resolvers` 沒給就不送。
- `import_mode = "SPICE"` 要帳號有 SPICE 容量，而且 module 不排程重新整理，只是把 dataset 建成 SPICE 模式。
- dataset 的 `columns` 要跟查詢結果的欄位名稱與型別一致；module 不會替你推斷欄位。
- QuickSight 文件寫：在主控台改過 data source 後，secret 會被自動拿掉。如果有人在主控台改過 Redshift 來源，要重新 apply，必要時用 API 的 `update-data-source` 把 secret 補回去（Terraform 是否偵測得到這個差異，沒有驗證過）。
- 這個 module 只做過離線的靜態驗證與 mock plan，還沒在真實帳號 apply 過。以下都要在真實環境驗證：Athena 來源用專用 role 能查、Redshift 來源用 secret 能連（含授權步驟與部署身分的讀取權限）、VPC connection 變成 `AVAILABLE`、dataset 能預覽資料、權限 action 足夠使用者建分析。

## 刻意不做

QuickSight 帳號訂閱、user、group、namespace、folder、analysis、dashboard、refresh schedule、row-level security、其他資料來源類型（S3、RDS、Aurora 等）、IAM role 與 policy（用 `iam-role`、`iam-role-policy`）、security group（用 `security-group`）。Redshift 來源不收 `credential_pair`：那會讓資料庫密碼進 state，這個 module 只接受 secret ARN。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `aws_account_id` | `string` | 無 | 是 | QuickSight 資源所在的 AWS 帳號 ID（12 位數字）。QuickSight 的 data source、dataset、VPC connection 都以帳號與 region 為範圍，ID 在同一個帳號與 region 內必須唯一。 |
| `athena_sources` | `map(object)` | `{}` | 否 | Athena data source，key 同時是 data source 的 ID 與名稱（1–128 字元，限英數字、`_`、`-`）。`workgroup` 是查詢用的 Athena workgroup；`role_arn` 是這個 data source 專用的 IAM role ARN（覆蓋帳號層預設 role，module 不建 role）。role 的信任對象是 `quicksight.amazonaws.com`，權限限於這個 workgroup 的查詢、資料來源 bucket 與查詢結果 bucket 的讀寫、Glue catalog 讀取與用到的 KMS key。 |
| `redshift_sources` | `map(object)` | `{}` | 否 | Redshift data source，key 同時是 data source 的 ID 與名稱（1–128 字元，限英數字、`_`、`-`，不可跟 `athena_sources` 的 key 重複）；空 map 就一個都不建。`host`、`port`（預設 5439）、`database` 是連線目標；`secret_arn` 是 Secrets Manager secret 的 ARN，secret 要有 `username`、`password`，用專用的唯讀 DB user，secret 在 repo 外建立。Redshift 來源只支援 secret，module 沒有帳密輸入。要先在 QuickSight 主控台把這個 secret 授權給 QuickSight，且執行 Terraform 的身分要有這個 secret 的 `secretsmanager:GetSecretValue`。有任何 Redshift 來源就必須給 `vpc_connection`。連線一律開 SSL。 |
| `vpc_connection` | `object` | `null` | 否 | QuickSight 連進 VPC 的 VPC connection；`null` 不建（只有 Athena 來源時用）。`name` 同時是 connection 的 ID 與名稱（1–128 字元，限英數字、`_`、`-`）；`role_arn` 是 QuickSight 建 ENI 用的 IAM role ARN（module 不建 role，信任 `quicksight.amazonaws.com`，需要 `ec2:CreateNetworkInterface`、`ec2:ModifyNetworkInterfaceAttribute`、`ec2:DeleteNetworkInterface`、`ec2:DescribeSubnets`、`ec2:DescribeSecurityGroups`）；`subnet_ids` 2–15 個（provider 不接受單一 subnet；建議放在不同 AZ，module 驗不了），`security_group_ids` 1–16 個（security group 由呼叫端建，要能連到 Redshift 的 port）；`dns_resolvers` 選填，自有 DNS 才需要。VPC connection 需要 QuickSight Enterprise 版。 |
| `datasets` | `map(object)` | `{}` | 否 | dataset，key 同時是 dataset 的 ID、名稱與 logical table 別名（1–128 字元，限英數字、`_`、`-`）。`source_key` 是 `athena_sources` 或 `redshift_sources` 的 key；資料來源用 `sql`（自訂 SQL）或 `table`（`name`、`schema`、`catalog` 指到來源上的表，Athena 的 `catalog` 是 `AwsDataCatalog`、`schema` 是 Glue database），兩者恰好給一個；`columns` 至少一個，`type` 是 `STRING`、`INTEGER`、`DECIMAL`、`DATETIME`、`BIT`、`BOOLEAN`、`JSON`、`SEMISTRUCT`，要跟查詢結果的欄位一致；`import_mode` 是 `DIRECT_QUERY`（預設，每次查詢都打來源）或 `SPICE`（要帳號有 SPICE 容量，module 不排程重新整理）。 |
| `owner_principals` | `list(string)` | `[]` | 否 | 擁有者的 QuickSight user 或 group ARN（`arn:aws:quicksight:<identity region>:<account>:user/<namespace>/<name>` 或 `group/<namespace>/<name>`）。對每個 data source 與 dataset 取得檢視、修改、刪除與改權限的 action（data source 6 個、dataset 10 個）。不能同時出現在 `reader_principals`。QuickSight 帳號、user、group 由 module 以外管理。 |
| `reader_principals` | `list(string)` | `[]` | 否 | 唯讀使用者的 QuickSight user 或 group ARN，格式同 `owner_principals`。對每個 data source 取得檢視與 pass 的 action（3 個），對每個 dataset 取得檢視、pass 與查詢 ingestion 的 action（5 個）。不能同時出現在 `owner_principals`。 |
| `tags` | `map(string)` | `{}` | 否 | 每個 resource 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `data_source_arns` | data source 的 ARN，key 是 `athena_sources` 與 `redshift_sources` 的 key。 |
| `data_set_arns` | dataset 的 ARN，key 是 `datasets` 的 key。 |
| `vpc_connection_arn` | VPC connection 的 ARN；沒給 `vpc_connection` 時是 `null`。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/quicksight-data
```
