# account-security-defaults

管理帳號在一個 region 的安全預設：S3 account public access block、EBS 預設加密、新 instance 預設用 IMDSv2，以及 IAM 使用者的密碼政策。只改帳號的預設值，不動既有的 bucket、volume 與 instance。

## 用法

```hcl
module "defaults" {
  source = "git::https://github.com/<org>/<repo>.git//modules/account-security-defaults?ref=account-security-defaults-v0.1.0"

  ebs_default_kms_key_arn = module.key.key_arn
}

# 其他 region 只管 regional 的設定
module "defaults_us_east_1" {
  source = "git::https://github.com/<org>/<repo>.git//modules/account-security-defaults?ref=account-security-defaults-v0.1.0"

  region                 = "us-east-1"
  s3_public_access_block = false
  password_policy        = null
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 範圍 | 值 |
|---|---|---|
| S3 account public access block | 帳號全域 | 四項全開 |
| EBS 預設加密 | region | 開；`ebs_default_kms_key_arn` 有給就用那把 key，沒給用 `aws/ebs` |
| IMDS 預設值 | region | `http_tokens = "required"`、`http_put_response_hop_limit = 2`，其他欄位不設（沿用 AWS 預設） |
| 密碼政策 | 帳號全域 | 最短 14 字元、四種字元都要、90 天到期、記住 24 組、使用者可以自己改 |

## 注意

- **S3 public access block 與密碼政策是帳號全域設定，一個帳號只能有一份。** 同一個帳號在多個 region 呼叫時，只有主 region 那一份管這兩項，其他 region 給 `s3_public_access_block = false`、`password_policy = null`；兩份 state 都管會互相覆蓋。
- `false` 與 `null` 是「不管理」，不是「關掉」。從開改成不管理時，Terraform 會從 state 移除 resource：public access block 會被刪掉（等於關掉），EBS 預設加密與 IMDS 預設值則是恢復 AWS 的預設。要保留設定，就不要改成不管理。
- 開了 S3 account public access block 之後，帳號裡所有 bucket 都不能公開，包括用 public ACL 或 public policy 的靜態網站。要公開的內容用 CloudFront 加 OAC（`s3-bucket` 的 `cloudfront_distribution_arns`）。
- EBS 預設加密開了之後，用沒加密的 snapshot 或 AMI 開 instance 也會產生加密的 volume。用客戶管理的 key 時，key policy 要允許用到 EBS 的服務（EC2 Auto Scaling 的 service-linked role、跨帳號分享 AMI 的帳號），否則開機會失敗。
- IMDS 的 hop limit 是 2，讓 instance 上的 container 也能拿到 IMDS；只影響之後建立的 instance，啟動範本或 module 自己有設 metadata options 的話以那邊為準。
- 密碼政策只管 IAM 使用者的 console 密碼，跟 IAM Identity Center 無關。
- 這個 module 用到 `aws_iam_account_password_policy`，是 `validate.sh` S4 唯一允許的 `aws_iam_*` 例外（design v10 K3）：它是帳號設定，不是權限。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

IAM role、user 與 policy、密碼的 `hard_expiry`、IMDS 的其他欄位（`http_endpoint`、`instance_metadata_tags`）、S3 bucket 層的 public access block（由 `s3-bucket` 管）、AMI 與 snapshot 的 block public access、Organizations 的 SCP。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `region` | `string` | `null` | 否 | EBS 預設加密、EBS 預設 key 與 IMDS 預設值所在的 region；`null`（預設）用 provider 的 region。S3 account public access block 與密碼政策是帳號全域設定，不受影響。 |
| `s3_public_access_block` | `bool` | `true` | 否 | `true` 管理帳號層的 S3 public access block，四項全開。`false` 不管理，帳號原本的設定不變；從 `true` 改成 `false` 會移除這項設定。一個帳號只能有一份，第二個 region 呼叫時給 `false`。 |
| `ebs_encryption_by_default` | `bool` | `true` | 否 | `true` 在這個 region 開 EBS 預設加密。`false` 不管理，原本的設定不變；從 `true` 改成 `false` 會關掉預設加密。 |
| `ebs_default_kms_key_arn` | `string` | `null` | 否 | EBS 預設加密用的客戶管理 KMS key ARN（`arn:aws:kms:<region>:<帳號>:key/<id>`）。`null` 用 AWS 管理的 `aws/ebs`。要有 `ebs_encryption_by_default = true`。 |
| `imdsv2_default` | `bool` | `true` | 否 | `true` 把這個 region 新 instance 的 IMDS 預設值設成 `http_tokens = "required"`（IMDSv2）、`http_put_response_hop_limit = 2`。`false` 不管理。只影響之後建立的 instance。 |
| `password_policy` | `object` | `{}` | 否 | IAM 使用者的密碼政策（帳號全域）。欄位：`minimum_length`（14–128，預設 14）、`require_symbols`、`require_numbers`、`require_uppercase`、`require_lowercase`（預設都是 `true`）、`max_age_days`（1–1095，預設 90）、`reuse_prevention`（1–24，預設 24）、`allow_users_to_change`（預設 `true`）。`null` 不管理；一個帳號只能有一份，第二個 region 呼叫時給 `null`。 |

## 輸出

| 名稱 | 說明 |
|---|---|
<!-- END_TF_DOCS -->
