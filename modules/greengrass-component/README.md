# greengrass-component

建一個 Greengrass v2 元件版本：recipe 直接寫在 Terraform 裡（HCL 物件或 JSON 字串擇一），artifact 只能放在指定的 S3 bucket。artifact 由 CI 上傳，這個 module 不上傳物件。用 awscc provider（aws provider 沒有 Greengrass v2 的 resource）。

## 用法

```hcl
module "inference_1_0_0" {
  source = "git::https://github.com/<org>/<repo>.git//modules/greengrass-component?ref=greengrass-component-v0.1.0"

  artifact_bucket_name = "alpha-dev-greengrass-artifacts"
  recipe_json          = file("${path.module}/components/com.example.Inference/1.0.0.json")

  tags = { Project = "alpha", Environment = "dev" }
}
```

recipe 用 HCL 物件寫的例子見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| recipe 格式 | `RecipeFormatVersion` 必須是 `2020-01-25`；`ComponentVersion` 是 semver |
| 元件類型 | 只收 generic 元件（`ComponentType` 不給或 `aws.greengrass.generic`），不建 Lambda 元件 |
| artifact | 每個 `Manifests[*].Artifacts[*].Uri` 都要以 `s3://<artifact_bucket_name>/` 開頭 |
| 元件名稱 | 不能以 `aws.greengrass.` 開頭（AWS 提供的元件） |
| recipe 編碼 | `recipe_json` 會先解析再 `jsonencode`，只改空白或縮排不會重建 |
| tag | 給定的 `tags` 加上 `Name`（元件名稱），以 map 傳給 resource |

## 注意

- **元件版本不能改。** recipe 只要有任何變動，Terraform 就會刪掉舊的版本、再建一個同版號的版本（replace）。要改元件就發新版本：新增一份 recipe、版號往上加，舊版本留到沒有部署在用為止。
- **刪掉還在部署的版本，部署會失敗。** AWS 允許刪除被部署引用的版本，但引用它的部署之後會失敗。範本用 precondition 檢查部署引用的版本都有對應的 recipe 檔；直接用這個 module 時，要自己確認沒有部署還在用。
- artifact 上傳後不能換內容（Greengrass 建版本時會記下 digest），要換就發新版本。所以 recipe 要在 artifact 上傳之後才 apply。
- core device 的 token exchange role 要另外給 `artifact_bucket_name` 的 `s3:GetObject`，AWS 的預設 policy 不含 S3 物件的讀取。
- `inline_recipe` 在 CloudFormation 是 write-only 屬性，awscc 1.107.0 的 schema 把它標成 optional＋computed。apply 之後 plan 會不會一直顯示變更，要在真實帳號確認；如果會，再加 `ignore_changes` 並更新這段。
- awscc 透過 Cloud Control API 建立資源，錯誤訊息與 drift 偵測比 aws provider 少。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

Lambda 元件（`lambda_function`）、上傳 artifact、公開元件、YAML recipe、Docker 或其他非 S3 的 artifact。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `recipe` | `any` | `null` | 否 | 元件的 recipe，用 HCL 物件寫（欄位名稱照 Greengrass recipe 的 JSON 格式，例如 `ComponentName`、`ComponentVersion`、`Manifests`），module 會 `jsonencode`。跟 `recipe_json` 擇一。`RecipeFormatVersion` 必須是 `2020-01-25`，`ComponentVersion` 是 semver，所有 artifact 的 `Uri` 都要在 `artifact_bucket_name` 裡。 |
| `recipe_json` | `string` | `null` | 否 | 元件的 recipe，JSON 字串（例如 `file("components/com.example.Inference/1.0.0.json")`）。跟 `recipe` 擇一，規則相同；不收 YAML。 |
| `artifact_bucket_name` | `string` | 無 | 是 | 放 artifact 的 S3 bucket 名稱（不含 `s3://`）。recipe 裡每個 artifact 的 `Uri` 都必須以 `s3://<artifact_bucket_name>/` 開頭；core device 的 token exchange role 要能 `s3:GetObject` 這個 bucket。 |
| `tags` | `map(string)` | `{}` | 否 | 元件版本的 tag；`Name`（元件名稱）由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `arn` | 元件版本的 ARN。 |
| `component_name` | 元件名稱。 |
| `component_version` | 元件版本。部署引用這個 output 時，會等元件版本建好才建部署。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/greengrass-component
```
