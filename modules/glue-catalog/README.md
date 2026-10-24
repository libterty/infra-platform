# glue-catalog

建 Glue Data Catalog 的 database。資料管線裡 raw、curated 這幾層的 table 都掛在這些 database 底下，Athena、Redshift Spectrum、Glue crawler 與 Glue job 都從這裡讀寫 metadata。

## 用法

```hcl
module "catalog" {
  source = "git::https://github.com/<org>/<repo>.git//modules/glue-catalog?ref=glue-catalog-v0.1.0"

  databases = {
    alpha_dev_raw = {
      description  = "Raw zone, crawled from the raw bucket"
      location_uri = "s3://alpha-dev-raw/raw/"
    }
    alpha_dev_curated = {
      description = "Curated zone, written by the ETL jobs"
    }
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 名稱 | key 就是 database 名稱，只收小寫英文字母、數字、`_`，1–255 字元 |
| 空輸入 | `databases = {}` 不建任何 resource |
| tag | 給定的 `tags` 加上 `Name`（database 名稱） |

## 注意

- database 名稱不收大寫與 `-`：Glue 會把名稱轉成小寫存，而 Athena 與 Redshift Spectrum 的 identifier 只穩定支援小寫英文字母、數字與 `_`，在 validation 就擋掉，不必等到查詢才出錯。
- 名稱在同帳號、同 region 內唯一；改名等於刪掉再建，掛在底下的 table 也會一起消失（table 通常由 crawler 或 Glue job 建立，不在這個 module 管）。
- `location_uri` 只是 database 的預設位置，不授權任何存取；讀寫 S3 與 catalog 的權限由呼叫端給各自的 role。
- catalog 的 at-rest 加密是帳號加 region 層級的設定，不在這裡；見 [`glue-catalog-encryption`](../glue-catalog-encryption/README.md)。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

table、帳號層加密（用 `glue-catalog-encryption`）、Lake Formation 權限、catalog resource policy、federated database、resource link（`target_database`）、`create_table_default_permission`。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `databases` | `map(object)` | 無 | 是 | 要建的 Glue database，key 是 database 名稱（小寫英文字母、數字、`_`，1–255 字元；Athena 與 Redshift Spectrum 只收這種名稱），值是 `description` 與 `location_uri`（`s3://` 開頭，沒給就不設）。空的 map 不建任何東西。 |
| `tags` | `map(string)` | `{}` | 否 | 每個 database 的 tag；`Name` 由 module 加上，值是 database 名稱。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `database_names` | 建好的 database 名稱，由小到大排序。 |
| `database_arns` | database 名稱對應 ARN 的 map。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/glue-catalog
```
