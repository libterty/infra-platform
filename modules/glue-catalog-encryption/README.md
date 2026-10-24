# glue-catalog-encryption

用客戶管理的 KMS key 加密 Glue Data Catalog：catalog metadata（database、table、partition 等）用 `SSE-KMS`，connection 的密碼也用同一把 key，而且在 `GetConnection` 的回應裡保持加密。

這是帳號加 region 層級的設定，一個 catalog 只有一份。**每個帳號、每個 region 只能由一處呼叫**（帳號 baseline 或平台 stack），後 apply 的會蓋掉前面的設定。**開了之後，所有讀寫這個 catalog 的身分都要有這把 key 的權限**（`kms:Decrypt`、`kms:Encrypt`、`kms:GenerateDataKey`），包括同帳號的其他專案、Athena、Redshift Spectrum、crawler 與 Glue job 的 role。**同帳號的第二個專案不要再呼叫，把呼叫端的選填輸入設成 `null`**，否則兩個專案互相蓋掉對方的 key。

## 用法

```hcl
module "glue_catalog_encryption" {
  source = "git::https://github.com/<org>/<repo>.git//modules/glue-catalog-encryption?ref=glue-catalog-encryption-v0.1.0"

  kms_key_arn = module.key.key_arn
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| metadata 加密 | `encryption_at_rest.catalog_encryption_mode = "SSE-KMS"`，key 是必填輸入 `kms_key_arn` |
| connection 密碼 | 用同一把 key 加密，`return_connection_password_encrypted = true` |
| service role | 不委派（不設 `catalog_encryption_service_role`），呼叫端各自要有 KMS 權限 |
| catalog | 不給 `catalog_id`，用 provider 的預設（本帳號的 catalog） |

## 注意

- **開啟後所有存取 catalog 的身分都需要 KMS 權限**，沒有權限的身分讀寫 catalog 會失敗。key policy 或每個 role 的 IAM policy 要給 `kms:Decrypt`、`kms:Encrypt`、`kms:GenerateDataKey`；建立或更新 connection 的呼叫者至少要有 `kms:Encrypt`。這個 module 不管 key policy 與 IAM。
- 同帳號多個專案共用一個 catalog，所以只有一個專案可以管這份設定。其他專案的呼叫端要設成 `null`（不呼叫這個 module），並且確認自己的 role 有這把 key 的權限。
- `kms_key_arn` 只收客戶管理 key 的 ARN（含 multi-Region key），不收 alias 與裸 key id。Glue 只支援 symmetric key。
- 加密只作用在開啟之後新寫入的物件；AWS 文件寫明停用加密後，既有已加密的物件仍維持加密，所以 key 在這些物件還存在時不能刪。
- 文件也寫明：crawler 處理過加密的 catalog 之後再移除加密設定，會讓 crawler 出錯，要移除設定時改建新的 crawler 而不是修改舊的。
- **destroy 的行為**：provider 的 delete 對 catalog 送一份空的 `DataCatalogEncryptionSettings`（`PutDataCatalogEncryptionSettings`，見 provider 原始碼 `resourceDataCatalogEncryptionSettingsDelete`）。AWS 文件沒有明寫空設定會不會把 catalog 改回不加密，這點還沒在真實帳號驗證；destroy 前後都用 `aws glue get-data-catalog-encryption-settings` 確認。不管結果如何，先前已加密的物件需要原來的 key，destroy 後不要馬上刪 key。
- 部署者要有 `glue:PutDataCatalogEncryptionSettings`、`glue:GetDataCatalogEncryptionSettings`。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

`catalog_encryption_service_role`（`SSE-KMS-WITH-SERVICE-ROLE`）、跨帳號 catalog（`catalog_id`）、關閉加密的選項、`DISABLED` 模式。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `kms_key_arn` | `string` | 無 | 是 | 加密 Glue Data Catalog 的客戶管理 KMS key ARN（symmetric），必填。catalog metadata（`SSE-KMS`）與 connection 密碼都用這把 key。**這是帳號加 region 層級的設定，每個帳號、每個 region 只能由一處呼叫**；開了之後，所有讀寫 catalog 的身分（包括同帳號其他專案）都要在 key policy 或自己的 IAM policy 取得這把 key 的 `kms:Decrypt`、`kms:Encrypt`、`kms:GenerateDataKey`。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `catalog_id` | 套用這份加密設定的 Data Catalog ID（就是帳號 ID）。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/glue-catalog-encryption
```
