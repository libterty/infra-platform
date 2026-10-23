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

## 容易出錯的地方

| 坑 | 這裡怎麼做 |
|---|---|
| 省略 `tier_config` 就是 `CLASSIC`，`CLASSIC` 只評估英文，中文完全不擋；guardrail 照樣 `READY`、plan 乾淨 | 預設 `STANDARD`，`content_policy_config` 與 `topic_policy_config` 兩塊都明寫 `tier_config`；要 `CLASSIC` 必須明寫 |
| `STANDARD` 的 profile id 寫錯，apply 照樣成功，要到第一個真實請求才失敗 | validation 只擋得到格式（像 `apac.guardrail.v1:0`）。**profile id 對不對只有實際呼叫 `ApplyGuardrail` 驗得到**，換 region 或換 profile 之後要打一次真實請求 |
| 發佈 guardrail 版本之後，apply 只改 `DRAFT`，實際生效的是舊版，plan 乾淨 | 這個 module 不建 `aws_bedrock_guardrail_version`，`version` 輸出固定 `DRAFT`；呼叫端一律用 `DRAFT`，apply 的改動就是線上的政策。`scripts/validate.sh` 的 S9 擋整個 repo 出現這個 resource |
| 輸入那支加了 PII 遮罩（`ANONYMIZE`），Bedrock 仍回報 `GUARDRAIL_INTERVENED`，應用程式若把它當成「被擋」，整輪對話就斷掉 | 不做成 validation（判斷在應用程式）。**PII 遮罩放在輸出那支**；放在輸入時，應用程式要分辨「被擋」與「被遮罩」 |

## 注意

- **`version` 輸出固定是 `DRAFT`，對 guardrail 的任何修改都會立刻生效。** 呼叫端用的就是 `DRAFT`，沒有「先發佈版本、再切換」的緩衝：`terraform apply`、Console 或 API 對這支 guardrail 的修改，下一個請求就套用。建議用 SCP 或 permission boundary 把 `bedrock:UpdateGuardrail`（以及 `bedrock:DeleteGuardrail`）限制成只有部署用的 role 能呼叫，避免有人在 Console 改掉政策而 Terraform 下次 apply 前都沒人發現。這個 module 不建 IAM，也不建這條限制。
- `CLASSIC` 只有在 `tier` 明寫時才會用到，預設一律 `STANDARD`。
- **建好資源還不會生效。** guardrail 建好、IAM 也給了，應用程式沒有呼叫 `ApplyGuardrail`（或沒有在模型呼叫時帶上 guardrail），guardrail 就沒有作用。
- `STANDARD` 的 `ApplyGuardrail` 另外對 guardrail profile 授權，AWS 會動態選 region，IAM 的 Resource 要寫 `arn:<partition>:bedrock:*:<account>:guardrail-profile/<profile_id>`（region 用 `*`，profile id 用確切值）。這個 module 不建 IAM，`cross_region_profile_id` 輸出給 IAM 那邊用。
- `PROMPT_ATTACK` 只評估輸入，`output_strength` 必須是 `NONE`，其他值 API 會拒絕。
- denied topic 沒有 `input_enabled`／`output_enabled`；要只作用在某一側，就放在只有那一側會呼叫的那支 guardrail。排除條件只能寫在 `definition`，`examples` 只放正面例子。
- 每種 policy 的輸入為空時整塊不送（Bedrock 拒收空清單）；但至少要有一種 policy。
- `kms_key_arn` 只收 `arn:aws:kms:<region>:<account>:key/<uuid>` 或 multi-region key 的 `key/mrk-<32 碼>`，alias 與 `*` 都擋。給自管 key 時，key policy 要允許 Bedrock 使用；需要哪些 principal 與條件**未實測**。
- `pii_entities` 的 key 只收 aws provider 6.69.0 驗證的 31 種 PII 類型（全大寫，例如 `EMAIL`、`PHONE`、`CREDIT_DEBIT_CARD_NUMBER`、`US_SOCIAL_SECURITY_NUMBER`），清單取自 provider 在 plan 時回報的允許值，跟 AWS 文件的 `GuardrailPiiEntityConfig` 一致。module 先擋是為了讓錯誤指到 `pii_entities`；AWS 新增類型時要跟著 provider 版本更新這份清單。
- 下列 validation 是照 AWS 文件或單一實例推出來的，**未實測**：profile id 的格式、PII 與 regex 的 action、grounding 門檻 0–0.99、「至少一種 policy」。

## 刻意不做

- `aws_bedrock_guardrail_version`（見上面的坑）。
- IAM：`bedrock:ApplyGuardrail` 由呼叫端的 role 給，用 `iam-role` 或 `iam-role-policy`。
- `input_modalities`／`output_modalities`：只處理文字。
- word、managed word list、PII、regex 的 `input_action`／`output_action`：全部用預設，需要時再加（MINOR）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | guardrail 名稱，1–50 個英數字、`-`、`_`。 |
| `description` | `string` | `null` | 否 | guardrail 的說明。 |
| `blocked_input_message` | `string` | 無 | 是 | 輸入被擋時，取代 prompt 回給使用者的文字。 |
| `blocked_output_message` | `string` | 無 | 是 | 輸出被擋時，取代模型輸出回給使用者的文字。 |
| `tier` | `string` | `"STANDARD"` | 否 | `STANDARD` 或 `CLASSIC`。`CLASSIC` 只評估英文，非英文的文字完全不擋。 |
| `cross_region_profile_id` | `string` | `null` | 否 | `tier` 是 `STANDARD` 時必填；`CLASSIC` 時必須是 `null`。guardrail profile id，例如 `apac.guardrail.v1:0`。沒有 API 驗證這個值，寫錯要到第一個真實請求才會失敗。 |
| `content_filters` | `map(object)` | `{}` | 否 | content filter，key 是類型：`SEXUAL`、`VIOLENCE`、`HATE`、`INSULTS`、`MISCONDUCT`、`PROMPT_ATTACK`。欄位：`input_strength`、`output_strength`（必填，`NONE`、`LOW`、`MEDIUM`、`HIGH`；`PROMPT_ATTACK` 的 `output_strength` 必須是 `NONE`）、`input_action`、`output_action`（`BLOCK` 或 `NONE`，預設 `BLOCK`）、`input_enabled`、`output_enabled`（預設 `true`）。 |
| `denied_topics` | `map(object)` | `{}` | 否 | denied topic，key 是 topic 名稱，最多 30 個。欄位：`definition`（必填、不可空白，排除條件只能寫在這裡）、`examples`（預設 `[]`，只放正面例子）。 |
| `words` | `list(string)` | `[]` | 否 | 自訂封鎖字詞。 |
| `managed_word_lists` | `set(string)` | `[]` | 否 | AWS 管理的字詞清單，只收 `PROFANITY`。 |
| `pii_entities` | `map(object)` | `{}` | 否 | PII 過濾，key 是 PII 類型（全大寫，例如 `EMAIL`、`PHONE`，只收 aws provider 6.69.0 驗證的 31 種）。欄位：`action`（`BLOCK` 或 `ANONYMIZE`；`ANONYMIZE` 仍會回報 intervention）、`input_enabled`、`output_enabled`（預設 `true`）。 |
| `regexes` | `map(object)` | `{}` | 否 | 自訂 regex 過濾，key 是名稱。欄位：`pattern`、`action`（`BLOCK` 或 `ANONYMIZE`）、`description`（選填）。 |
| `contextual_grounding` | `object` | `null` | 否 | contextual grounding 門檻。欄位：`grounding_threshold`、`relevance_threshold`，各 0–0.99，至少給一個。`null` 時不設定。 |
| `kms_key_arn` | `string` | `null` | 否 | guardrail 用的自管 KMS key ARN（`key/<uuid>` 或 `key/mrk-<32 碼>`，不收 alias 與 `*`）。`null` 時用 AWS 擁有的 key。 |
| `tags` | `map(string)` | `{}` | 否 | guardrail 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `guardrail_id` | guardrail id。 |
| `guardrail_arn` | guardrail ARN。 |
| `name` | guardrail 名稱。 |
| `version` | 呼叫端要用的版本，固定 `DRAFT`（不讀 resource 的 `version`），因為這個 module 不發佈版本；對 guardrail 的修改立刻生效。 |
| `cross_region_profile_arn` | `STANDARD` 時是 guardrail profile ARN；`CLASSIC` 時是 `null`。 |
| `cross_region_profile_id` | guardrail profile id；`CLASSIC` 時是 `null`。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/bedrock-guardrail
```
