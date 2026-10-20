# bedrock-inference-profile

建 Bedrock 的 application inference profile，用途只有一個：成本歸屬。每個 profile 帶自己的 tag，呼叫端把 profile 的 ARN 當 `modelId` 傳，Cost Explorer 就能依 tag 拆出這個專案、這個用途的模型費用。`profiles` 是空 map 時什麼都不建。

## 用法

```hcl
module "inference_profile" {
  source = "git::https://github.com/<org>/<repo>.git//modules/bedrock-inference-profile?ref=bedrock-inference-profile-v0.1.1"

  name_prefix = "alpha-dev"

  profiles = {
    chat = {
      copy_from   = "arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-3-5-sonnet-20240620-v1:0"
      description = "Chat traffic for alpha-dev"
    }
    embedding = {
      copy_from = "arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }

  tags = {
    Project = "alpha"
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 容易出錯的地方

- **`copy_from` 要給完整 ARN，不是 model id。** 只給 `anthropic.claude-...` 或 `apac.anthropic.claude-...` 這種 id，要到 apply 才會失敗。module 在 plan 階段只放行 `foundation-model` 與 `inference-profile`（system inference profile）兩種 ARN；`provisioned-model` 與 `application-inference-profile` 都擋。ARN 最後一段只收 `[A-Za-z0-9._:-]`，含 `*` 的 ARN 會被擋。
- **system inference profile 的 ARN 帶的是呼叫端自己的帳號。** `inference-profile/` 的 ARN 帳號欄必須等於目前的帳號（module 用 `aws_caller_identity` 比對，不符時 profile resource 的 precondition 擋下），帳號欄空白也擋；foundation-model ARN 的帳號欄本來就是空的，不受影響。
- **名稱上限 64 字。** 名稱是 `<name_prefix>-<key>`，超過會在 plan 階段被擋，不用等到 apply。
- **profile 是 `ACTIVE` 不代表能呼叫。** 模型使用權（Marketplace 訂閱、use case 申請）是逐帳號的設定，這個 module 不管；沒開通的模型，profile 一樣建得起來，要到第一次真實呼叫才失敗。

## 注意

- 名稱字元規則照 AWS 文件（`^([0-9a-zA-Z:.][ _-]?)+$`：字母、數字、`:`、`.`，中間可以夾一個空白、`_` 或 `-`，不能連續兩個），**未實測**。
- system inference profile（例如 `apac.`、`global.` 前綴）會把請求路由到其他 region。呼叫端的 IAM 除了 application inference profile 本身的 ARN，還要允許來源 profile 與 foundation model 的 ARN（foundation model 的 region 欄要用 `*`）。這些權限由範本的 `iam-app` 組，這個 module 不建 IAM。
- `tags` 套用到每個 profile，另外自動加 `Name`（值是 profile 名稱 `<name_prefix>-<key>`，跟其他 module 一致）；成本是靠 tag 拆的，tag 要在 Billing 啟用成 cost allocation tag，才會出現在 Cost Explorer。

## 刻意不做

- 模型使用權（`aws_bedrock_foundation_model_agreement`、`aws_bedrock_use_case_for_model_access`）：逐帳號、牽涉 Marketplace 訂閱，不適合放在專案 module。
- provisioned throughput。
- IAM：呼叫 profile 的權限在範本的 `iam-app`，ARN 由 `agent` stack 的 `models` 統一組。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name_prefix` | `string` | 無 | 是 | profile 名稱前綴，名稱為 `<name_prefix>-<key>`，總長不得超過 64 字 |
| `profiles` | `map(object)` | 無 | 是（可以是 `{}`） | key 為 profile 短名。欄位：`copy_from`（必填，foundation model 或 system inference profile 的完整 ARN，不能含 `*`；system inference profile 必須在目前的帳號）、`description`（預設 `null`） |
| `tags` | `map(string)` | `{}` | 否 | 套用到每個 profile 的 tag，Cost Explorer 依這些 tag 拆模型費用；另外自動加 `Name`（profile 名稱） |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `arns` | `map(string)` | application inference profile 的 ARN，key 為 `profiles` 的 key；呼叫端把它當 `modelId` 傳 |
| `ids` | `map(string)` | application inference profile 的 id，key 為 `profiles` 的 key |

## 測試

```bash
scripts/validate.sh modules/bedrock-inference-profile
```
