# bedrock-knowledge-base

建一個 Bedrock Knowledge Base（`VECTOR` 型）與它的 S3 data source。向量存在專案自己的 Aurora PostgreSQL（pgvector），**只收 Aurora**，其他向量儲存不做。

module 只負責接線，並在 plan 時擋掉名稱與欄位對應寫錯的輸入。`vector` extension、表、索引、KB 專用的資料庫帳號由專案的 migration 建，**資料庫裡有沒有那張表，module 驗不到**。要先跑的 SQL 見 design §4.30〈資料庫要先準備好的東西〉，可照抄的完整版本會收在 `docs/guides/llm-agentcore.md`。

沒有任何參考專案用過 Bedrock Knowledge Base，這個 module 的依據只有 aws provider 6.69.0 的 schema 與 AWS 文件。標「未實測」的行為都列在 design §7.3 第 21 項。

## 用法

```hcl
module "knowledge_base" {
  source = "git::https://github.com/<org>/<repo>.git//modules/bedrock-knowledge-base?ref=bedrock-knowledge-base-v0.1.1"

  name                 = "alpha-dev-docs"
  role_arn             = var.kb_role_arn
  embedding_model_arn  = "arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.titan-embed-text-v2:0"
  embedding_dimensions = 1024 # 必須等於表的 vector(N)

  aurora = {
    cluster_arn            = var.aurora_cluster_arn
    credentials_secret_arn = var.kb_credentials_secret_arn # KB 專用帳號的 secret，不是 master secret
    database_name          = "app"
    table_name             = "bedrock_integration.bedrock_kb"
  }

  data_sources = {
    manuals = {
      bucket_arn              = module.kb_corpus.arn
      bucket_owner_account_id = data.aws_caller_identity.current.account_id
      inclusion_prefixes      = ["manuals/"]
    }
  }
}
```

完整範例見 [`examples/aurora-pgvector/`](./examples/aurora-pgvector/main.tf)。

## 部署前要先完成的事

順序是：Aurora 開 Data API（`rds` 的 `data_api`）→ 專案建 KB 帳號的 secret、跑 migration、設密碼 → 這個 module。KB 建立時 Bedrock 會不會檢查表與欄位、還是要到第一次 ingestion 才失敗，**未實測**；順序照「建立時就會檢查」排。

| 對照 | SQL（design §4.30） | module 輸入 |
|---|---|---|
| 表 | `bedrock_integration.bedrock_kb` | `aurora.table_name` |
| 主鍵 | `id uuid` | `aurora.field_mapping.primary_key_field`（預設 `id`） |
| 向量 | `embedding vector(1024)` | `aurora.field_mapping.vector_field`（預設 `embedding`）、`embedding_dimensions = 1024` |
| 文字 | `chunks text` | `aurora.field_mapping.text_field`（預設 `chunks`） |
| metadata | `metadata json` | `aurora.field_mapping.metadata_field`（預設 `metadata`） |
| 自訂 metadata | `custom_metadata jsonb` | `aurora.field_mapping.custom_metadata_field`（預設 `null`，有給才送；SQL 的這一欄與它的索引也只有這時才需要） |
| 資料庫帳號 | `bedrock_kb_user` | `aurora.credentials_secret_arn` 指向的 secret 的 `username` |

## 要修掉的坑

這個 module 沒有參考實作可以對照，下面是相對於 AWS 文件範例刻意改掉的地方：

- **KB 連資料庫用專用帳號，不用 master secret。** AWS 文件的範例對 KB 帳號給 `GRANT ALL ON SCHEMA`，並讓 KB 帳號自己建表。這裡表由 migration 建，KB 帳號只有那張表的 `SELECT`、`INSERT`、`UPDATE`、`DELETE` 與 schema 的 `USAGE`。module 拿不到 master secret 的 ARN，擋不了；範本的 `agent` 用 precondition 擋。Bedrock 在 ingestion 與查詢時是否需要更多權限，**未實測**，不夠時只在那張表上補缺的那一項。
- **`data_deletion_policy` 預設 `RETAIN`。** 刪掉 data source 時不連帶清掉向量，避免一次錯誤的 apply 清空知識庫。要跟著刪的專案明寫 `DELETE`。
- **`custom_metadata_field` 預設不送。** 有給才送，SQL 不用多建一欄。
- **名稱一律小寫識別字。** `database_name`、`table_name` 的每一段、`field_mapping` 的五個欄位都只收 `^[a-z_][a-z0-9_]{0,62}$`，避免 SQL 裡要加雙引號才對得上。

## 注意

- **`aurora.cluster_arn` 與 `aurora.credentials_secret_arn` 必須跟 provider 在同一個帳號、同一個 region。** module 用 `aws_caller_identity`、`aws_region` 比對 ARN 的帳號與 region 欄，不符時 plan 被 KB resource 的 precondition 擋下。
- **`credentials_secret_arn` 要給完整的 secret ARN**，含 Secrets Manager 自動加上的 `-` 加 6 個字元尾碼，不收 `*` 或只到名稱為止的 ARN。
- **每個 data source 都要寫 `bucket_owner_account_id`**（12 位數字）。它必須等於目前的帳號；bucket 在別的帳號時，要把那個帳號列進 `allowed_account_ids`，否則 plan 被 data source 的 precondition 擋下。Bedrock 用這個值確認 bucket 的擁有者，避免讀到別人同名的 bucket。
- `role_arn` 允許帶 path，但 path 的每一段都不能是空的（`role//x`、結尾是 `/` 都會被擋）。規則跟 `agentcore-runtime`、`agentcore-gateway` 相同。
- `kms_key_arn` 只收 `arn:aws:kms:<region>:<account>:key/<uuid>` 或 multi-region key 的 `key/mrk-<32 碼>`，alias 與 `*` 都擋。
- **`aurora.cluster_arn` 必須是 Aurora cluster 的 ARN**（`:cluster:`），DB instance 的 ARN（`:db:`）會被擋：Bedrock 經 RDS Data API 連資料庫，Data API 只支援 Aurora cluster。用 `rds` module 時就是 `arn` 輸出（部署型態 `aurora` 或 `aurora_serverless`）。
- **`embedding_dimensions` 必須等於 SQL 的 `vector(N)`。** module 驗不到資料庫，只能靠上面的對照表。
- `embedding_model_arn` 只收 foundation-model ARN，inference profile 與含 `*` 的 ARN 會被擋。
- `field_mapping` 的欄位名不能重複。重複時 KB 寫入會互相覆蓋（推論，**未實測**）。
- data source 的名稱就是 `data_sources` 的 key，規則跟 KB 名稱相同。
- chunking 只收 `FIXED_SIZE`（預設 300 token、重疊 20%）與 `NONE`。`NONE` 時不送 `fixed_size_chunking_configuration`。`overlap_percentage` 1–99、`max_tokens` 大於 0；provider 6.69.0 在 plan 時也擋 `overlap_percentage` 1–99 以外的值。
- `inclusion_prefixes` 不能以 `/` 開頭；空集合時不送，表示整個 bucket。
- `kms_key_arn` 套到每個 data source 的 `server_side_encryption_configuration`（ingestion 過程的暫存資料）。key policy 要給什麼**未實測**。
- KB 帳號的 secret 不由 RDS 管理，沒有自動輪替。換密碼時 secret 與 `ALTER ROLE` 要一起改，中間 ingestion 與查詢會認證失敗；KB 會不會快取 secret，**未實測**。
- ingestion 不是資源。文件上傳後由人或 CI 呼叫 `StartIngestionJob`。
- `tags` 只套用到 KB（data source 沒有 tag），另外自動加 `Name`。

## 刻意不做

- ingestion job：執行期的動作，不是資源。
- 其他向量儲存（S3 Vectors、OpenSearch Serverless 等）。
- `HIERARCHICAL`、`SEMANTIC` chunking、parsing、custom transformation。
- 語料 bucket：範本的 `agent` 用 `s3-bucket` 建，module 不呼叫 module。
- 資料庫帳號與它的 secret：專案的 migration 與流程負責。
- IAM：KB role 的權限在 `iam-app`。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | KB 的完整名稱。字母、數字、`-`、`_`，頭尾是字母或數字，最長 100 字 |
| `description` | `string` | `null` | 否 | KB 的說明 |
| `role_arn` | `string` | 無 | 是 | Bedrock KB service role 的 ARN（範本由 `iam-base` 建），可帶 path，每段不能是空的；module 不建 IAM |
| `embedding_model_arn` | `string` | 無 | 是 | 嵌入模型的 foundation-model ARN，不能含 `*` |
| `embedding_dimensions` | `number` | 無 | 是 | 向量維度，正整數，必須等於表的 `vector(N)` |
| `aurora` | `object` | 無 | 是 | 欄位：`cluster_arn`（Aurora cluster ARN，必須在目前的帳號與 region）、`credentials_secret_arn`（KB 專用帳號的 Secrets Manager secret 的完整 ARN，含 6 字元尾碼，必須在目前的帳號與 region，值是 `{"username","password"}`，**不要給 master secret**）、`database_name`（小寫識別字）、`table_name`（`<schema>.<table>` 或 `<table>`，每段小寫識別字）、`field_mapping`（選填，見下） |
| `aurora.field_mapping` | `object` | `{}` | 否 | `primary_key_field`（預設 `id`）、`vector_field`（預設 `embedding`）、`text_field`（預設 `chunks`）、`metadata_field`（預設 `metadata`）、`custom_metadata_field`（預設 `null`，不送）。都是小寫識別字、彼此不重複 |
| `data_sources` | `map(object)` | `{}` | 否 | key 為 data source 名稱。欄位：`bucket_arn`（S3 bucket ARN，必填）、`inclusion_prefixes`（預設空集合，不能以 `/` 開頭）、`bucket_owner_account_id`（必填，12 位數字，必須是目前的帳號或列在 `allowed_account_ids`）、`data_deletion_policy`（`RETAIN` 或 `DELETE`，預設 `RETAIN`）、`chunking`（`strategy` 為 `FIXED_SIZE` 或 `NONE`，預設 `FIXED_SIZE`；`max_tokens` 預設 300、大於 0；`overlap_percentage` 預設 20、1–99） |
| `allowed_account_ids` | `set(string)` | `[]` | 否 | 目前帳號以外、允許擁有 data source bucket 的帳號（12 位數字）。空集合表示只收同帳號的 bucket |
| `kms_key_arn` | `string` | `null` | 否 | data source ingestion 暫存資料的 KMS key ARN（`key/<uuid>`，不收 alias 與 `*`）；`null` 用 AWS 管的 key |
| `tags` | `map(string)` | `{}` | 否 | 套用到 KB 的 tag，另外自動加 `Name` |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `knowledge_base_id` | `string` | KB 的 id，給應用程式呼叫 `Retrieve` 與 `StartIngestionJob` 用 |
| `knowledge_base_arn` | `string` | KB 的 ARN，給 IAM 權限用 |
| `data_source_ids` | `map(string)` | data source 的 id，key 為 `data_sources` 的 key |

## 測試

```bash
scripts/validate.sh modules/bedrock-knowledge-base
```
