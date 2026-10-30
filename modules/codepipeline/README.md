# codepipeline

建一條 CodePipeline V2 pipeline：module 自己產生從 GitHub（CodeConnections）取程式碼的 source stage，後面接呼叫端給的 Build、Approval、Deploy 等 stage。pipeline 只能手動執行，push 不會自動觸發。

## 用法

```hcl
module "api_pipeline" {
  source = "git::https://github.com/<org>/<repo>.git//modules/codepipeline?ref=codepipeline-v0.1.0"

  name                 = "alpha-sit-api"
  role_arn             = module.pipeline_role.arn
  artifact_bucket_name = module.artifacts.bucket_name
  artifact_kms_key_arn = module.kms.key_arn

  git_source = {
    connection_arn = module.github.arn
    repository     = "example-org/example-app"
    branch         = "main"
  }

  stages = [
    {
      name = "Build"
      actions = [{
        name             = "api-build"
        category         = "Build"
        provider         = "CodeBuild"
        configuration    = { ProjectName = module.api_build.name }
        input_artifacts  = ["SourceArtifact"]
        output_artifacts = ["BuildArtifact"]
        namespace        = "BuildVariables"
      }]
    },
    {
      name    = "Approval"
      actions = [{ name = "approve", category = "Approval", provider = "Manual" }]
    },
  ]
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| pipeline 類型 | `V2` |
| 觸發 | 不建 `trigger`；source action 固定 `DetectChanges = "false"`，只能手動執行 |
| source stage | 名稱 `Source`，一個 `CodeStarSourceConnection` action（名稱 `Source`），輸出 artifact `SourceArtifact`，namespace `SourceVariables`，`OutputArtifactFormat = "CODE_ZIP"` |
| action | `owner = "AWS"`、`version = "1"` |
| artifact store | `S3`，用 `artifact_kms_key_arn` 加密（`encryption_key.type = "KMS"`） |
| 執行模式 | 預設 `QUEUED` |
| tag | 給定的 `tags` 加上 `Name` |

## 注意

- 手動執行：console 按「Release change」，或 `aws codepipeline start-pipeline-execution --name <name>`。執行時取 `git_source.branch` 的最新 commit。誰能執行由 IAM 決定（`codepipeline:StartPipelineExecution`），不在這個 module 裡。
- AWS 文件寫明 `DetectChanges = false` 時「CodePipeline does not start your pipeline on new commits」，沒有 trigger 的設定是「the pipeline does not start automatically on any change」。這個 module 只做過離線的靜態驗證，push 之後真的不會觸發要在真實帳號確認。
- connection 要先在 console 授權成 `AVAILABLE`（見 `codeconnections-connection`），不然 source stage 會失敗。
- service role 由呼叫端建：要有 `codeconnections:UseConnection` 與 `codestar-connections:UseConnection`（只給這個 connection）、artifact bucket 的讀寫、artifact key 的 `kms:Decrypt` 與 `kms:GenerateDataKey`，以及各 action 需要的權限（例如 CodeBuild 的 `StartBuild`、`BatchGetBuilds`）。
- action 的 `configuration` 是字串 map，值可以用 `#{SourceVariables.CommitId}`、`#{BuildVariables.IMAGE_URI}`、`#{variables.<name>}` 這類變數；CodeBuild 的 `EnvironmentVariables` 要自己 `jsonencode`。
- 後面的 stage 不能叫 `Source`，namespace 也不要用 `SourceVariables`，artifact 名稱不要用 `SourceArtifact`，這些名稱 module 已經用掉了。
- `QUEUED` 與 `PARALLEL` 只有 V2 pipeline 能用；AWS 的預設是 `SUPERSEDED`，這個 module 預設 `QUEUED`，避免後面的執行蓋掉還沒部署完的前一次。
- artifact bucket 要跟 pipeline 在同一個 region。

## 刻意不做

`trigger`（只能手動執行）、V1 pipeline、跨 region 或跨帳號 action（action 的 `region`、`role_arn`、多個 artifact store）、自訂 action type 與 `owner = "ThirdParty"`、`Compute` 類 action（`commands`）、`before_entry`、`on_success`、`on_failure` 條件、`timeout_in_minutes`、IAM role。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | pipeline 名稱，1–100 字元，限英數字、`.`、`@`、`-`、`_`。 |
| `role_arn` | `string` | 無 | 是 | pipeline 的 service role ARN，由呼叫端建立。role 要能用 `git_source.connection_arn`（`codeconnections:UseConnection` 與 `codestar-connections:UseConnection`）、讀寫 artifact bucket、用 artifact KMS key，以及呼叫各 action 需要的 API。 |
| `artifact_bucket_name` | `string` | 無 | 是 | 放 pipeline artifact 的 S3 bucket 名稱（不是 ARN），bucket 要跟 pipeline 在同一個 region。 |
| `artifact_kms_key_arn` | `string` | 無 | 是 | 加密 artifact 用的客戶管理 KMS key ARN（symmetric），必填，不收 alias。key policy 要讓 pipeline role 與各 CodeBuild role 有 `kms:Decrypt`、`kms:GenerateDataKey`。 |
| `git_source` | `object` | 無 | 是 | source stage 的設定，module 用它產生 `CodeStarSourceConnection` action（名稱 `Source`，輸出 artifact `SourceArtifact`，namespace `SourceVariables`），固定 `DetectChanges = "false"`、`OutputArtifactFormat = "CODE_ZIP"`。`connection_arn` 是 CodeConnections 的 connection ARN（`codeconnections` 或舊的 `codestar-connections` 前綴）；`repository` 是 `owner/name`；`branch` 是手動執行時取的分支。 |
| `stages` | `list(object)` | 無 | 是 | source stage 之後的 stage，至少一個，照順序排。stage 名稱不能重複，也不能叫 `Source`。每個 stage 至少一個 action，同一個 stage 裡 action 名稱不能重複。action 的 `category` 只收 `Approval`、`Build`、`Deploy`、`Invoke`、`Test`，`owner` 固定 `AWS`、`version` 固定 `1`；`configuration` 照各 action 的文件填，值可以用 `#{SourceVariables.CommitId}` 這類變數；source 的輸出 artifact 叫 `SourceArtifact`。 |
| `variables` | `map(object)` | `{}` | 否 | pipeline 層級的變數，key 是變數名稱（1–128 字元，限英數字、`@`、`-`、`_`），action 用 `#{variables.<name>}` 引用；手動執行時可以覆寫。 |
| `execution_mode` | `string` | `"QUEUED"` | 否 | 連續執行的處理方式：`QUEUED`（預設，依序執行、不會被後來的執行蓋掉）、`SUPERSEDED`、`PARALLEL`。 |
| `region` | `string` | `null` | 否 | pipeline 所在的 region；`null`（預設）用 provider 的 region。artifact bucket 要在同一個 region。 |
| `tags` | `map(string)` | `{}` | 否 | pipeline 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `name` | pipeline 名稱；手動執行用 `aws codepipeline start-pipeline-execution --name <name>`。 |
| `arn` | pipeline 的 ARN；給 IAM policy（`codepipeline:StartPipelineExecution`）與 EventBridge rule 的 `resources` 用。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/codepipeline
```
