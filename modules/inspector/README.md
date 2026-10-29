# inspector

在一個 region 啟用 Amazon Inspector 的掃描：預設 EC2、ECR、Lambda 套件弱點，Lambda 程式碼掃描預設關。在委派管理帳號可以替成員帳號啟用，或另給 `organization` 讓新成員自動啟用。

## 用法

```hcl
module "inspector" {
  source = "git::https://github.com/<org>/<repo>.git//modules/inspector?ref=inspector-v0.1.0"

  resource_types = ["EC2", "ECR", "LAMBDA"]
}
```

Organizations 模式（在資安帳號，也就是 Inspector 的委派管理帳號）：

```hcl
module "inspector" {
  source = "git::https://github.com/<org>/<repo>.git//modules/inspector?ref=inspector-v0.1.0"

  organization = {
    auto_enable = { ec2 = true, ecr = true, lambda = true }
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 掃描類型 | `resource_types` 預設 `EC2`、`ECR`、`LAMBDA`；只收這三種加 `LAMBDA_CODE` |
| 帳號 | `account_ids` 是 `[]` 時用目前帳號 |
| organization 自動啟用 | `ec2`、`ecr`、`lambda` 預設 `true`，`lambda_code` 預設 `false` |

## 注意

- **費用**：依掃描的 EC2 instance 數、ECR 映像數、Lambda 函式數計費，前 15 天試用。`LAMBDA_CODE` 依函式數另外計費，所以預設關，要開時 `LAMBDA` 也得開。
- **其他 region**：Inspector 是 regional 服務，要涵蓋其他 region 就用 `region` 多呼叫一次。
- **替其他帳號啟用**：`account_ids` 列別的帳號時，目前帳號要是 Inspector 的委派管理帳號，那些帳號也要已經是成員。委派本身由 `organization-delegated-admin` 在管理帳號做。
- **`organization` 只影響新成員**：既有成員要用 `account_ids` 列出來啟用。
- EC2 掃描預設靠 SSM agent，instance 要受 Systems Manager 管理才掃得到；hybrid（agentless）掃描模式不在這個 module。
- **停用會刪 finding**：destroy 這個 module 會停用列出的掃描類型，相關 finding 一併刪除。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

filter（suppression rule）、CIS scan、SBOM 匯出、code repository 掃描（`CODE_REPOSITORY`）、成員帳號關聯（`aws_inspector2_member_association`）、IAM。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `account_ids` | `list(string)` | `[]` | 否 | 要啟用掃描的帳號 ID（12 位數字）。`[]`（預設）用目前的帳號；列其他帳號時，目前帳號要是 Inspector 的委派管理帳號，而且那些帳號已經是成員。 |
| `resource_types` | `list(string)` | `[ "EC2", "ECR", "LAMBDA" ]` | 否 | 要啟用的掃描類型：`EC2`、`ECR`、`LAMBDA`（Lambda 套件弱點）、`LAMBDA_CODE`（Lambda 程式碼掃描，要同時開 `LAMBDA`）。預設 `EC2`、`ECR`、`LAMBDA`。 |
| `organization` | `object` | `null` | 否 | organization 的自動啟用設定，只在 Inspector 的委派管理帳號給。`auto_enable` 決定新成員帳號自動開哪些掃描：`ec2`、`ecr`、`lambda` 預設 `true`，`lambda_code` 預設 `false`（要同時開 `lambda`）。`null`（預設）時不管理 organization 設定。 |
| `region` | `string` | `null` | 否 | Inspector 所在的 region；`null`（預設）用 provider 的 region。Inspector 是 regional 服務，每個 region 各呼叫一次。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `enabled_resource_types` | 啟用的掃描類型（排序過）。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/inspector
```
