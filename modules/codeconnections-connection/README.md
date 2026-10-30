# codeconnections-connection

建一個 CodeConnections 的 connection，讓 CodePipeline 從 GitHub（或 GitLab、Bitbucket）拉程式碼。connection 建好後是 `PENDING`，要有人到 AWS console 授權一次才能用。

## 用法

```hcl
module "github" {
  source = "git::https://github.com/<org>/<repo>.git//modules/codeconnections-connection?ref=codeconnections-connection-v0.1.0"

  name = "alpha-dev-github"
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 平台 | `provider_type` 預設 `GitHub`；自架的 `GitHubEnterpriseServer`、`GitLabSelfManaged` 必須給 `host_arn`，雲端平台不能給 |
| `host_arn` | 給了 `host_arn` 時不設 `provider_type`（provider 不允許兩個同時給），平台類型由 host 決定 |
| region | 帶 `region`，`null` 用 provider 的 region |
| tag | 給定的 `tags` 加上 `Name`（connection 名稱） |

## 注意

- **apply 完 `status` 是 `PENDING`，Terraform 做不到授權。** 要有人到 AWS console 的 Developer Tools → Settings → Connections，選這個 connection 按「Update pending connection」，在 GitHub 安裝或選擇 AWS Connector for GitHub 這個 GitHub App，狀態才會變成 `AVAILABLE`。還是 `PENDING` 時，pipeline 的 source stage 會失敗。
- GitHub App 只裝在要部署的 repo，不要選 All repositories。
- 授權是 connection 層級的：刪掉重建（例如改名）之後要重新授權一次。
- 誰能用這個 connection 由 IAM 決定：pipeline role 的 `codeconnections:UseConnection` 只給這個 connection 的 ARN（`arn` 輸出）。
- connection 本身目前沒有查到單獨的收費項目：CodePipeline 與 CodeBuild 的價目頁沒有列 connection 的費用，AWS Price List 也沒有 CodeConnections 的項目。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

`aws_codeconnections_host`（自架 GitHub Enterprise Server 或 GitLab 的 host，要另外建）、connection 的授權步驟（只能在 console 做）、repository link 與 sync configuration。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | connection 名稱，1–32 字元。 |
| `provider_type` | `string` | `"GitHub"` | 否 | 程式碼平台：`GitHub`（預設）、`GitHubEnterpriseServer`、`GitLab`、`GitLabSelfManaged`、`Bitbucket`。自架的 `GitHubEnterpriseServer`、`GitLabSelfManaged` 必須給 `host_arn`。 |
| `host_arn` | `string` | `null` | 否 | 自架平台的 host ARN（`arn:<partition>:codeconnections:<region>:<account>:host/<id>`，舊的 `codestar-connections` 也接受）。只有 `GitHubEnterpriseServer`、`GitLabSelfManaged` 要給，雲端平台不能給。host 不由這個 module 建。 |
| `region` | `string` | `null` | 否 | connection 所在的 region；`null`（預設）用 provider 的 region。 |
| `tags` | `map(string)` | `{}` | 否 | connection 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `arn` | connection 的 ARN（`codepipeline` 的 source，以及 pipeline role 的 `codeconnections:UseConnection`）。 |
| `status` | connection 狀態。剛建好是 `PENDING`，要有人在 AWS console 完成授權後才會變成 `AVAILABLE`。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/codeconnections-connection
```
