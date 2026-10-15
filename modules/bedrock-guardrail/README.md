# bedrock-guardrail

建一支 Bedrock guardrail，`tier` 預設 `STANDARD`。一次呼叫一支；同一個專案要多支（例如輸入、輸出各一支，或依產品線分組），由 root 用 `for_each` 呼叫。

## 用法

```hcl
module "guardrail" {
  source = "git::https://github.com/<org>/<repo>.git//modules/bedrock-guardrail?ref=bedrock-guardrail-v0.1.1"

  name                    = "alpha-dev-input"
  blocked_input_message   = "Sorry, I cannot help with that request."
  blocked_output_message  = "Sorry, I cannot provide that answer."
  cross_region_profile_id = "apac.guardrail.v1:0"

  content_filters = {
    HATE          = { input_strength = "HIGH", output_strength = "HIGH" }
    PROMPT_ATTACK = { input_strength = "HIGH", output_strength = "NONE" }
  }
}
```

範例：

- [`examples/basic/`](./examples/basic/main.tf)：`STANDARD` 加 profile、六種 content filter、`PROFANITY`。
- [`examples/zh-tw-standard/`](./examples/zh-tw-standard/main.tf)：中文的 denied topic 與 content filter。

## 要修掉的坑

| 坑 | 這裡怎麼做 |
|---|---|
| 省略 `tier_config` 就是 `CLASSIC`，`CLASSIC` 只評估英文，中文完全不擋；guardrail 照樣 `READY`、plan 乾淨 | 預設 `STANDARD`，`content_policy_config` 與 `topic_policy_config` 兩塊都明寫 `tier_config`；要 `CLASSIC` 必須明寫 |
| `STANDARD` 的 profile id 寫錯，apply 照樣成功，要到第一個真實請求才失敗 | validation 只擋得到格式（像 `apac.guardrail.v1:0`）。**profile id 對不對只有實際呼叫 `ApplyGuardrail` 驗得到**，換 region 或換 profile 之後要打一次真實請求 |
| 發佈 guardrail 版本之後，apply 只改 `DRAFT`，實際生效的是舊版，plan 乾淨 | 這個 module 不建 `aws_bedrock_guardrail_version`，`version` 輸出固定 `DRAFT`；呼叫端一律用 `DRAFT`，apply 的改動就是線上的政策。`scripts/validate.sh` 的 S9 擋整個 repo 出現這個 resource |
| 輸入那支加了 PII 遮罩（`ANONYMIZE`），Bedrock 仍回報 `GUARDRAIL_INTERVENED`，應用程式若把它當成「被擋」，整輪對話就斷掉 | 不做成 validation（判斷在應用程式）。**PII 遮罩放在輸出那支**；放在輸入時，應用程式要分辨「被擋」與「被遮罩」 |

## 注意

- **資源就位不等於生效**：guardrail 建好、IAM 給了，應用程式沒有呼叫 `ApplyGuardrail`（或沒有在模型呼叫帶上 guardrail）就沒有效果。
- `STANDARD` 的 `ApplyGuardrail` 另外對 guardrail profile 授權，AWS 會動態選 region，IAM 的 Resource 要寫 `arn:<partition>:bedrock:*:<account>:guardrail-profile/<profile_id>`（region 用 `*`，profile id 用確切值）。這個 module 不建 IAM，`cross_region_profile_id` 輸出給 IAM 那邊用。
- `PROMPT_ATTACK` 只評估輸入，`output_strength` 必須是 `NONE`，其他值 API 會拒絕。
- denied topic 沒有 `input_enabled`／`output_enabled`；要只作用在某一側，就放在只有那一側會呼叫的那支 guardrail。排除條件只能寫在 `definition`，`examples` 只放正面例子。
- 每種 policy 的輸入為空時整塊不送（Bedrock 拒收空清單）；但至少要有一種 policy。
- `kms_key_arn` 給自管 key 時，key policy 要允許 Bedrock 使用；需要哪些 principal 與條件**未實測**。
- 下列 validation 照 AWS 文件或單一實例推出來，**未實測**：profile id 的格式、PII 與 regex 的 action、grounding 門檻 0–0.99、「至少一種 policy」。

## 刻意不做

- `aws_bedrock_guardrail_version`（見上面的坑）。
- IAM：`bedrock:ApplyGuardrail` 由呼叫端的 role 給，用 `iam-role` 或 `iam-role-policy`。
- `input_modalities`／`output_modalities`：只處理文字。
- word、managed word list、PII、regex 的 `input_action`／`output_action`：全部用預設，需要時再加（MINOR）。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | guardrail 名稱，1–50 個英數字、`-`、`_` |
| `description` | `string` | `null` | 否 | 說明 |
| `blocked_input_message` | `string` | 無 | 是 | 輸入被擋時回給使用者的文字 |
| `blocked_output_message` | `string` | 無 | 是 | 輸出被擋時回給使用者的文字 |
| `tier` | `string` | `"STANDARD"` | 否 | `STANDARD` 或 `CLASSIC`；`CLASSIC` 只評估英文 |
| `cross_region_profile_id` | `string` | `null` | `STANDARD` 時必填 | guardrail profile id，例如 `apac.guardrail.v1:0`；`CLASSIC` 必須是 `null` |
| `content_filters` | `map(object)` | `{}` | 否 | key 是 `SEXUAL`／`VIOLENCE`／`HATE`／`INSULTS`／`MISCONDUCT`／`PROMPT_ATTACK`；`input_strength`、`output_strength`（`NONE`／`LOW`／`MEDIUM`／`HIGH`，必填）、`input_action`、`output_action`（`BLOCK`／`NONE`，預設 `BLOCK`）、`input_enabled`、`output_enabled`（預設 `true`） |
| `denied_topics` | `map(object)` | `{}` | 否 | key 是 topic 名稱；`definition`（必填、不可空白）、`examples`（預設 `[]`）；最多 30 個 |
| `words` | `list(string)` | `[]` | 否 | 自訂封鎖字詞 |
| `managed_word_lists` | `set(string)` | `[]` | 否 | 只收 `PROFANITY` |
| `pii_entities` | `map(object)` | `{}` | 否 | key 是 PII 類型（例如 `EMAIL`、`PHONE`）；`action`（`BLOCK`／`ANONYMIZE`）、`input_enabled`、`output_enabled`（預設 `true`） |
| `regexes` | `map(object)` | `{}` | 否 | key 是名稱；`pattern`、`action`（`BLOCK`／`ANONYMIZE`）、`description`（選填） |
| `contextual_grounding` | `object` | `null` | 否 | `grounding_threshold`、`relevance_threshold`，各 0–0.99，至少給一個 |
| `kms_key_arn` | `string` | `null` | 否 | 自管 KMS key；`null` 用 AWS 的 key |
| `tags` | `map(string)` | `{}` | 否 | guardrail 的 tag；`Name` 由 module 加上 |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `guardrail_id` | `string` | guardrail id |
| `guardrail_arn` | `string` | guardrail ARN |
| `name` | `string` | guardrail 名稱 |
| `version` | `string` | 固定 `"DRAFT"`，不讀 resource 的 `version` |
| `cross_region_profile_arn` | `string` | `STANDARD` 時是 guardrail profile ARN；`CLASSIC` 時是 `null` |
| `cross_region_profile_id` | `string` | profile id；`CLASSIC` 時是 `null` |

## 測試

```bash
scripts/validate.sh modules/bedrock-guardrail
```
