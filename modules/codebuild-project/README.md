# codebuild-project

建一個給 CodePipeline 呼叫的 CodeBuild 建置專案，加上它自己的 log group。source 與 artifact 固定是 `CODEPIPELINE`：程式碼由 pipeline 交給它，專案本身不連 GitHub、不建 webhook。建置輸出一律用客戶管理的 KMS key 加密。

## 用法

```hcl
module "api_build" {
  source = "git::https://github.com/<org>/<repo>.git//modules/codebuild-project?ref=codebuild-project-v0.1.0"

  name               = "alpha-dev-api-build"
  service_role_arn   = module.api_build_role.role_arn
  encryption_key_arn = module.pipeline_key.key_arn
  buildspec          = "ci/api/buildspec.yml"

  environment = {
    privileged_mode = true
  }

  environment_variables = {
    IMAGE_REPO = { value = "alpha/api" }
    NPM_TOKEN  = { value = "/alpha/dev/npm-token", type = "PARAMETER_STORE" }
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| source、artifact | 都是 `CODEPIPELINE`；沒有 repo 位址、沒有 GitHub 認證、沒有 webhook |
| 加密 | 建置輸出用 `encryption_key_arn`（必填），不用 AWS 管理的 key |
| 建置環境 | 預設 `ARM_CONTAINER`、`BUILD_GENERAL1_SMALL`（價目表的 `arm1.small`）、`aws/codebuild/amazonlinux-aarch64-standard:3.0`，不開 `privileged_mode` |
| log | CloudWatch Logs 開，寫到 module 建的 log group；S3 log 關 |
| 公開程度 | `project_visibility = "PRIVATE"` |
| 快取 | 預設不快取；建映像檔的專案開 `privileged_mode` 後可以加 `cache_modes = ["LOCAL_DOCKER_LAYER_CACHE"]`。`LOCAL_SOURCE_CACHE` 對 `CODEPIPELINE` source 沒有作用 |
| region | 建置專案與 log group 都帶 `region`，`null` 用 provider 的 region |
| tag | 給定的 `tags` 加上 `Name`（各自的名稱） |

## 注意

- **buildspec 會用 service role 的全部權限。** 能改 repo 裡 buildspec 的人，就能用這個 role 做任何它允許的事。每個元件各用一個 role，只給那個元件需要的 resource；被部署的分支要開 branch protection，只能透過 PR 合併。
- **`PLAINTEXT` 變數不放 secret。** 名稱含 `PASSWORD`、`SECRET`、`TOKEN`、`KEY` 的 `PLAINTEXT` 變數會被拒，因為值會留在專案設定與 Terraform state 裡。改用 `PARAMETER_STORE`（`value` 是參數名稱）或 `SECRETS_MANAGER`（`value` 是 `<secret-id>:<json-key>`），並在 service role 明確給那一個參數或 secret 的讀取權限（加上解密用的 KMS 權限）。這個檢查只看名稱，像 `KMS_KEY_ID` 這種不是 secret 的名稱也會被擋，換個名稱或改用 `PARAMETER_STORE`。
- **`type` 決定架構，不是 `compute_type`。** `BUILD_GENERAL1_SMALL` 配 `ARM_CONTAINER` 是 ARM，配 `LINUX_CONTAINER` 是 x86。CodeBuild 的 curated 映像名稱有架構（`aarch64`、`x86_64`，Ubuntu 的 `aws/codebuild/standard` 只有 x86），跟 `type` 不一致會被拒；自訂映像（例如 ECR）不檢查，要自己確認架構。
- 自訂映像用 CodeBuild 的憑證拉取（`image_pull_credentials_type` 是預設的 `CODEBUILD`）：私有 ECR repository 的 policy 要允許 `codebuild.amazonaws.com` 拉映像。
- **`privileged_mode` 只給要跑 `docker build` 的專案開。** 開了之後建置容器能操作 Docker daemon，權限比一般建置大。`LOCAL_DOCKER_LAYER_CACHE` 也只在 privileged 的專案有作用。
- `LOCAL_SOURCE_CACHE` 只快取 Git 的 metadata；source 是 `CODEPIPELINE` 時程式碼由 pipeline 以 artifact 交付，這個模式多半沒有作用。本機快取只留在同一台建置主機上，不保證命中。
- `ARM_CONTAINER` 不是每個 region 都有；ap-northeast-1 與 us-east-1 都有，其他 region 先查 CodeBuild 文件的 region 限制。
- `encryption_key_arn` 的 key policy 要允許 service role 使用（`kms:GenerateDataKey`、`kms:Decrypt`）；pipeline 的 artifact bucket 也用同一把時，pipeline role 也要。`log_kms_key_arn` 的 key policy 要允許 `logs.<region>.amazonaws.com`。
- service role 要能寫這個 log group（`log_group_name` 輸出）。module 自己建 log group，預設 `/aws/codebuild/<name>`、保留 30 天，不接受 0（永不過期）。
- `concurrent_build_limit` 預設 `1`：同一個專案同時只跑一個建置，部署不會互相覆蓋；超過的建置在佇列等，等超過 `queued_timeout` 就失敗。
- 免費額度是每月 100 分鐘的 `general1.small` 或 `arm1.small`。ap-northeast-1 的 `arm1.small` 是每分鐘 0.00425 美元、`general1.small` 是 0.005 美元（AWS Price List，2026-09-11 發布）。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

webhook 與 GitHub 直連（專案只從 pipeline 執行）、batch build、reserved capacity fleet、VPC 設定、report group、Lambda compute、S3 快取、S3 log、secondary source 與 artifact、IAM role（用 `iam-role` 建）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | 建置專案名稱，2–255 字元，限英數字、`-`、`_`，英數字開頭。log group 預設名稱是 `/aws/codebuild/<name>`。 |
| `description` | `string` | `null` | 否 | 建置專案的說明，最多 255 字元；`null`（預設）不設。 |
| `service_role_arn` | `string` | 無 | 是 | 建置專案的 service role ARN，用 `iam-role` 建。至少要能寫這個 log group、讀寫 pipeline 的 artifact bucket、用 `encryption_key_arn` 這把 key；buildspec 會用這個 role 的全部權限，每個元件各用一個 role。 |
| `buildspec` | `string` | `null` | 否 | buildspec：source repo 裡的路徑（例如 `ci/api/buildspec.yml`）或 inline YAML；`null`（預設）用 repo 根目錄的 `buildspec.yml`。 |
| `environment` | `object` | `{}` | 否 | 建置環境。欄位：`compute_type`（`BUILD_GENERAL1_SMALL`（預設）、`_MEDIUM`、`_LARGE`、`_XLARGE`、`_2XLARGE`）、`image`（預設 `aws/codebuild/amazonlinux-aarch64-standard:3.0`）、`type`（`ARM_CONTAINER`（預設）或 `LINUX_CONTAINER`，要跟映像的架構一致）、`privileged_mode`（預設 `false`；在建置裡跑 `docker build` 的專案要開）。 |
| `environment_variables` | `map(object)` | `{}` | 否 | 建置的環境變數，名稱對應 `{ value, type }`。`type` 是 `PLAINTEXT`（預設）、`PARAMETER_STORE`（`value` 是參數名稱）、`SECRETS_MANAGER`（`value` 是 `<secret-id>:<json-key>` 這類參照）。名稱要以字母或底線開頭，限英數字與底線；`PLAINTEXT` 的名稱像 secret（含 `PASSWORD`、`SECRET`、`TOKEN`、`KEY`）會被拒，要改用另外兩種類型。 |
| `encryption_key_arn` | `string` | 無 | 是 | 加密建置輸出 artifact 的客戶管理 KMS key ARN（`key/<id>`，不接受 alias），必填。通常跟 pipeline artifact bucket 用同一把。 |
| `log_group_name` | `string` | `null` | 否 | module 建的 log group 名稱，1–512 字元，限英數字與 `.`、`-`、`_`、`/`、`#`；`null`（預設）用 `/aws/codebuild/<name>`。 |
| `log_retention_days` | `number` | `30` | 否 | log group 的保留天數，必須是 CloudWatch Logs 接受的值（例如 `1`、`7`、`30`、`365`），不接受 `0`（永不過期）。 |
| `log_kms_key_arn` | `string` | `null` | 否 | log group 的客戶自管 KMS key ARN（`key/<id>`，不接受 alias）。key policy 必須允許 `logs.<region>.amazonaws.com`。 |
| `build_timeout` | `number` | `30` | 否 | 單次建置的逾時分鐘數，5–2160 的整數。 |
| `queued_timeout` | `number` | `60` | 否 | 建置在佇列等待的逾時分鐘數，5–480 的整數。 |
| `concurrent_build_limit` | `number` | `1` | 否 | 同時執行的建置數上限，至少 1 的整數。預設 `1`，同一個專案的部署不會重疊。 |
| `cache_modes` | `list(string)` | `[]` | 否 | 本機快取模式，值是 `LOCAL_DOCKER_LAYER_CACHE`、`LOCAL_SOURCE_CACHE`、`LOCAL_CUSTOM_CACHE`，不可重複；`[]`（預設）時不快取。`LOCAL_DOCKER_LAYER_CACHE` 要搭配 `environment.privileged_mode = true`。 |
| `region` | `string` | `null` | 否 | 建置專案與 log group 所在的 region；`null`（預設）用 provider 的 region。 |
| `tags` | `map(string)` | `{}` | 否 | 建置專案與 log group 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `name` | 建置專案名稱（`codepipeline` 的 build action 的 `ProjectName`）。 |
| `arn` | 建置專案的 ARN（pipeline role 的 `codebuild:StartBuild`、`codebuild:BatchGetBuilds` 的 resource）。 |
| `log_group_name` | module 建的 log group 名稱（service role 寫 log 的 resource）。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/codebuild-project
```
