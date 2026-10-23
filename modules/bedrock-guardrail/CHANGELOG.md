# Changelog

## [0.1.2](https://github.com/libterty/infra-platform/compare/bedrock-guardrail-v0.1.1...bedrock-guardrail-v0.1.2) (2026-10-23)


### Bug Fixes

* **bedrock-guardrail:** rewrite the input and output descriptions in Chinese ([b82d8ed](https://github.com/libterty/infra-platform/commit/b82d8ed699a329c8f3ab4a8ad8c8bf7dee361e3a))

## 0.1.1（2026-10-16）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立一支 `aws_bedrock_guardrail`，`tier` 預設 `STANDARD`，`content_policy_config` 與 `topic_policy_config` 兩塊都明寫 `tier_config`。
- `STANDARD` 時送 `cross_region_config`，profile ARN 由 partition、region、帳號與 `cross_region_profile_id` 組成；`CLASSIC` 時不送。
- 每種 policy 在對應輸入為空時整塊不送；denied topic 一律是 `DENY`。
- 擋下：名稱不是 1–50 個英數字、`-`、`_`；`tier` 不是 `STANDARD`／`CLASSIC`；`STANDARD` 沒給或給了格式不符的 profile id、`CLASSIC` 給了 profile id；content filter 的 key、strength、action 不在允許值內；`PROMPT_ATTACK` 的 `output_strength` 不是 `NONE`；超過 30 個 topic 或 `definition` 為空；PII 與 regex 的 action 不是 `BLOCK`／`ANONYMIZE`；managed word list 不是 `PROFANITY`；grounding 門檻不在 0–0.99 或兩個門檻都沒給；所有 policy 都空；`pii_entities` 的 key 不是 provider 6.69.0 的 31 種 PII 類型；`kms_key_arn` 不是 `key/<uuid>` 形式的 KMS key ARN（alias、`*` 都擋）。
- 輸出 `guardrail_id`、`guardrail_arn`、`name`、`version`（固定 `DRAFT`）、`cross_region_profile_arn`、`cross_region_profile_id`。
- README 寫明 `version` 固定 `DRAFT`、修改立刻生效，並建議用 SCP 或 permission boundary 把 `bedrock:UpdateGuardrail` 限制給部署用的 role。
- 不建 guardrail 版本、不建 IAM、不處理 `input_modalities`／`output_modalities`。
