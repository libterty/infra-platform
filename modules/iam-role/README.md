# iam-role

建立一個 IAM role：trust policy、inline policy，以及白名單內的 AWS managed policy。

整個 repo 只有這個 module 與 [`iam-role-policy`](../iam-role-policy/README.md) 可以宣告 `aws_iam_*` 資源（由 `scripts/validate.sh` 的 S4 規則強制檢查）。

## 用法

```hcl
module "ecs_execution" {
  source = "git::https://github.com/<org>/<repo>.git//modules/iam-role?ref=iam-role-v0.1.1"

  name = "alpha-dev-ecs-execution"

  trust = {
    service_principals = ["ecs-tasks.amazonaws.com"]
    source_account     = "111111111111"
  }

  inline_policies = {
    ecr-pull = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      }]
    })
  }
}
```

EKS Pod Identity 用的 role（0.3.0 起）：

```hcl
module "ebs_csi" {
  source = "git::https://github.com/<org>/<repo>.git//modules/iam-role?ref=iam-role-v0.3.0"

  name = "alpha-dev-ebs-csi"

  trust = {
    service_principals = ["pods.eks.amazonaws.com"]
    tag_session        = true
  }

  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicyV2"]
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf) 與 [`examples/pod-identity/`](./examples/pod-identity/main.tf)。

## 行為

- trust policy 只有一段 statement：`sts:AssumeRole`，Principal 是傳進來的服務主體。給了 `source_account` 才加 `StringEquals` 的 `aws:SourceAccount` 條件；給了 `source_arn`（0.1.1 起）才加 `ArnLike` 的 `aws:SourceArn` 條件。兩個都給時，兩個條件放在同一段 statement 裡，必須同時成立。
- policy 一律傳 JSON 字串（用 `jsonencode()`），不收 `aws_iam_policy_document` 的輸出。
- `arn` 輸出帶 `depends_on = [aws_iam_role_policy.this]`，所以下游拿到 ARN 時，inline policy 已經附加好了。
- Allow statement 的 Action 不可是 `*` 或以 `:*` 結尾；Deny statement 不受限。
- Allow statement 不可使用 `NotAction`（等於授權「列出的動作以外全部」）；沒寫 `Effect` 視為 Allow。Deny 搭配 `NotAction` 不受限。
- Allow statement 不可使用 `NotResource`（等於授權「列出的資源以外全部」）；沒寫 `Effect` 視為 Allow。Deny 搭配 `NotResource` 不受限。

- `managed_policy_arns` 內的每個 ARN 建一個 `aws_iam_role_policy_attachment`（0.3.0 起）。
- `trust.tag_session = true` 時 Action 是 `["sts:AssumeRole", "sts:TagSession"]`；預設 `false`，trust policy 的 JSON 跟 0.2.0 完全一樣。
- `trust.federated` 有值時（IRSA），statement 改成 `Federated` principal 加 `sts:AssumeRoleWithWebIdentity`，`StringEquals` 條件為 `<issuer>:sub = subject` 與 `<issuer>:aud = sts.amazonaws.com`。`<issuer>` 是 `oidc_provider_arn` 去掉 `arn:aws:iam::<帳號>:oidc-provider/` 前綴的部分。

## 注意

- AWS managed policy 的白名單寫在 `locals.tf`，ARN 路徑還沒在真實環境核對（設計文件 §6），第一次用之前要先核對。
- 0.4.0 起白名單加入 `CloudWatchAgentServerPolicy`，給 Container Insights 的採集元件（CloudWatch agent 與 Fluent Bit 共用的 ServiceAccount）用，見 v4 設計文件 W2。
- 0.5.0 起白名單加入 `service-role/AWS_ConfigRole`、`service-role/AWSBackupServiceRolePolicyForBackup`、`service-role/AWSBackupServiceRolePolicyForRestores`，給 Config recorder 與 AWS Backup 的 role 用，見 v10 設計文件 §8.1。
- 設計文件寫的 `AmazonEKSBlockStoragePolicyV2` 未確認是否真的存在，白名單暫時同時放 `AmazonEKSBlockStoragePolicy` 與 `AmazonEKSBlockStoragePolicyV2`，核對後只留一個。
- `AmazonEBSCSIDriverPolicyV2` 的 ARN 帶 `service-role/` 路徑；不帶路徑的寫法會被拒絕。
- IRSA（`federated`）只建議用在 Fargate，因為 Fargate 不支援 Pod Identity；其他 workload 用 Pod Identity（`pods.eks.amazonaws.com` 加 `tag_session`）。兩套並存會讓權限審查要看兩個地方，所以 `subject` 一定要指到單一 service account，不收萬用字元。
- `federated` 不能跟 `service_principals`、`tag_session`、`source_account`、`source_arn` 同時給；`federated` 的條件由 module 固定產生。

## 限制

- 只掛白名單內的 AWS managed policy，不收其他 AWS managed policy 與 customer managed policy。理由：EKS 的 cluster role、node role、Auto Mode、EBS CSI 以 AWS managed policy 為標準，內容由 AWS 更新，改寫成 inline 容易漏權限；白名單以外一律拒絕，避免有人掛 `AdministratorAccess` 之類的 policy。instance profile 只能用 `instance_profile_name` 建一個，綁在這個 role 上（0.2.0 起）。
- trust 只收 AWS 服務主體與單一 service account 的 OIDC（`federated`），不收 AWS 帳號或 `*`。
- `source_arn` 只檢查 `arn:` 開頭，不檢查 service、region、帳號是否與服務主體相符；萬用字元要放多寬由呼叫端決定。
- 不用任何獨佔管理 inline policy 的資源（例如 provider 的 role policies exclusive 類型），因為用了會刪掉 `iam-role-policy` 附加的 policy。
- 只檢查 Action、`NotAction`、`NotResource`，不檢查 `Resource`；`Resource = "*"` 合不合理由呼叫端的測試負責。
- `Statement` 必須是清單（單一物件的寫法會被擋）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | role 名稱，1–64 字元，限字母、數字與 `+=,.@_-`。 |
| `description` | `string` | `null` | 否 | role 的說明；`null` 時不設定。 |
| `trust` | `object` | 無 | 是 | trust policy：`service_principals` 與 `federated`（IRSA）二選一，其他欄位只能搭配 `service_principals`。欄位見〈`trust` 欄位〉。 |
| `managed_policy_arns` | `set(string)` | `[]` | 否 | 要掛的 AWS managed policy ARN，每個建一個 attachment。只收 `locals.tf` 白名單內的 ARN；customer managed policy 與白名單以外的 AWS managed policy 一律拒絕。 |
| `inline_policies` | `map(string)` | `{}` | 否 | inline policy 名稱對 policy JSON 字串（用 `jsonencode()` 產生）。每份 JSON 的 `Statement` 必須是清單；Allow statement（沒寫 `Effect` 視為 Allow）的 Action 不可是 `*` 或以 `:*` 結尾，也不可用 `NotAction`、`NotResource`；Deny statement 不受限。 |
| `permissions_boundary` | `string` | `null` | 否 | permissions boundary 的 policy ARN；`null` 時不設定。 |
| `instance_profile_name` | `string` | `null` | 否 | instance profile 名稱。有給就建一個綁這個 role 的 instance profile，`null` 時不建。1–128 字元，限字母、數字與 `_+=,.@-`。 |
| `tags` | `map(string)` | `{}` | 否 | 額外的 tag；module 只再加 `Name`。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `arn` | role ARN；所有 inline policy 與 managed policy 都附加好之後才有值。 |
| `name` | role 名稱。 |
| `id` | role ID。 |
| `instance_profile_name` | instance profile 名稱；沒給 `instance_profile_name` 時為 `null`。 |
| `instance_profile_arn` | instance profile ARN；沒給 `instance_profile_name` 時為 `null`。 |
<!-- END_TF_DOCS -->

## `trust` 欄位

`service_principals` 與 `federated` 二選一，不能同時給，也不能都不給。

| 欄位 | 預設 | 說明 |
|---|---|---|
| `service_principals` | `[]` | AWS 服務主體，例如 `ecs-tasks.amazonaws.com`、`pods.eks.amazonaws.com`；每個都要符合 `*.amazonaws.com`，不可含萬用字元 |
| `tag_session` | `false` | `true` 時 Action 加上 `sts:TagSession`；Pod Identity 與 EKS Auto Mode 需要。只能搭配 `service_principals` |
| `source_account` | `null` | 12 位數字的帳號 ID；有給才加 `StringEquals` 的 `aws:SourceAccount` 條件。只能搭配 `service_principals` |
| `source_arn` | `null` | 以 `arn:` 開頭、不含空白，可含萬用字元（例如 `arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/*`）；有給才加 `ArnLike` 的 `aws:SourceArn` 條件。只能搭配 `service_principals` |
| `federated.oidc_provider_arn` | 無（`federated` 有給時必填） | IRSA 用的 OIDC provider ARN，格式 `arn:aws:iam::<12 位帳號>:oidc-provider/<issuer>` |
| `federated.subject` | 無（`federated` 有給時必填） | 單一 service account，格式 `system:serviceaccount:<namespace>:<serviceaccount>`，不可含萬用字元 |

## 測試

```bash
scripts/validate.sh modules/iam-role
```
