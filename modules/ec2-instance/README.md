# ec2-instance

一台放在 private subnet 的 EC2：沒有 public IP、沒有 SSH key、強制 IMDSv2、root 與資料碟都加密。可以掛額外的資料碟，也可以選擇建 `StatusCheckFailed_System` 告警，在硬體出問題時自動 recover。需要自動補機器的情境用 `ec2-asg`。

## 用法

```hcl
module "app" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ec2-instance?ref=ec2-instance-v0.1.0"

  name                  = "alpha-dev-app"
  subnet_id             = module.vpc.private_subnet_ids[0]
  security_group_ids    = [module.app_sg.id]
  instance_profile_name = module.app_role.instance_profile_name
  instance_type         = "t4g.small"

  ebs_volumes = {
    data = { device_name = "/dev/sdf", size = 100 }
  }

  sns_topic_arns = [module.alarm_topic.arn]

  tags = {
    Project = "alpha"
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

連線：

```bash
aws ssm start-session --target "$(terraform output -raw instance_id)"
```

## 注意

- **沒有 public IP，也沒有 key pair。** `associate_public_ip_address` 明確寫 `false`，subnet 開了 auto-assign public IP 也不會生效；沒有 `key_name` 輸入。進去的唯一方式是 Session Manager，所以 `instance_profile_name` 要帶 `AmazonSSMManagedInstanceCore` 的權限（用 `iam-role` 建），subnet 要能連到 SSM endpoint（NAT，或 `ssm`、`ssmmessages`、`ec2messages` 的 VPC endpoint）。對外流量經 ALB 或 NLB。
- **固定的安全設定，沒有開關**：IMDSv2 必須、hop limit 1、root 與資料碟加密。`kms_key_arn` 是 `null` 時用帳號預設的 EBS KMS key，也可以給 key 的 ARN（不收 alias）。
- **`user_data` 以明文存在 state，也看得到在 EC2 console，不要放 secret。** 名稱含 `SECRET`、`PASSWORD`、`PASSWD`、`TOKEN`、`API_KEY`（也含 `API-KEY`）、`PRIVATE_KEY`、`CREDENTIAL` 的變數或設定直接寫了明文值（例如 `DB_PASSWORD=hunter2`、`x-api-key: abc`），或內容含有私鑰（`-----BEGIN … PRIVATE KEY-----`），會在 plan 時被擋下（不分大小寫）。值是從變數或指令取得的不擋，例如 `PASSWORD=$(aws secretsmanager get-secret-value ...)`、`TOKEN=$(curl ...)`。需要 secret 就讓機器開機後用 instance profile 從 Secrets Manager 取。上限 16384 bytes。`user_data` 改了，instance 會被停機再啟動套用，不會重建。
- **告警是選用的（D16）。** `sns_topic_arns` 預設 `[]`，空的就不建告警。這是 repo「會建告警的 module，`sns_topic_arns` 必填」慣例的例外。給了才會建 `<name>-status-check-system`：`alarm_actions` 有 `arn:aws:automate:<region>:ec2:recover` 與 SNS，`ok_actions` 只有 SNS。一個告警最多 5 個 action，所以 SNS 最多 4 個。
- AMI：`ami_id` 是 `null` 時，用 data source 找最新的 Amazon Linux 2023（依 `architecture`，不讀 SSM 參數）；有值就直接用，不查 data source。**`ignore_changes = [ami]`**：之後出了新 AMI，既有的 instance 不會被取代，要更新就用 `terraform apply -replace=module.app.aws_instance.this`。`ami_id` 輸出在沒給 `ami_id` 時是目前查到的最新 AMI，不一定是這台實際在用的。
- `instance_type` 必須跟 `architecture` 搭配：Graviton（`t4g`、`m7g`、`c6gn` 等）用 `arm64`，其他用 `x86_64`。module 看家族名稱判斷；舊的 `a1` 家族是 arm64 但不會被認出來，不支援。給了 `ami_id` 也一樣要跟 `architecture` 一致。
- `disable_api_termination` 預設 `true`；要 `terraform destroy` 或換掉 instance，先改成 `false` 並 apply。
- 資料碟是 `aws_ebs_volume` 加 `aws_volume_attachment`，建在 instance 所在的 AZ。`device_name` 限 `/dev/sdf` 到 `/dev/sdp`（或 `/dev/xvdf` 到 `/dev/xvdp`），同一台不能重複。module 只負責掛上，格式化與 mount 要在 `user_data` 或事後處理。
- security group 由 `security-group` module 建；這個 module 不建 security group、IAM、Elastic IP。

## 刻意不做

- SSH key、public IP、IMDSv1。
- IAM role 與 instance profile（用 `iam-role` 建）、security group（用 `security-group` 建）。
- 讀 SSM 參數取 AMI（只有 `ssm-read` 可以讀 SSM）。
- 多台、自動補機器（用 `ec2-asg`）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | instance 名稱，也是 `Name` tag，以及告警與資料碟名稱的前綴。2–63 字元，限小寫英數字與連字號，字母開頭。 |
| `subnet_id` | `string` | 無 | 是 | 放 instance 的 private subnet（`subnet-…` 格式）。instance 不會拿到 public IP。 |
| `security_group_ids` | `list(string)` | 無 | 是 | instance 的 security group（`sg-…` 格式），至少一個。 |
| `instance_profile_name` | `string` | 無 | 是 | instance profile 名稱，1–128 字元，要帶 SSM Session Manager 權限；沒有 SSH key。 |
| `instance_type` | `string` | 無 | 是 | instance type，例如 `t4g.small`，必須跟 `architecture` 搭配：Graviton 家族（`t4g`、`m7g`、`c6gn` 等）用 `arm64`，其他用 `x86_64`。 |
| `architecture` | `string` | `"arm64"` | 否 | `arm64` 或 `x86_64`。`ami_id` 為 `null` 時依這個值找 Amazon Linux 2023 AMI；給了 `ami_id` 也要一致。 |
| `ami_id` | `string` | `null` | 否 | 要啟動的 AMI（`ami-…` 格式）；`null` 時用 data source 找依 `architecture` 的最新 Amazon Linux 2023。 |
| `root_volume` | `object` | `{}` | 否 | root volume，一律是加密的 gp3。欄位：`size`（GiB，8–16384 的整數，預設 `20`）、`kms_key_arn`（KMS key ARN，不收 alias；預設 `null`，用帳號預設的 EBS key）。 |
| `ebs_volumes` | `map(object)` | `{}` | 否 | 額外的資料碟，key（小寫英數字與連字號，字母開頭，最多 41 字元）對應一顆 volume，一律加密，建在 instance 所在的 AZ。欄位：`device_name`（必填，`/dev/sdf`–`/dev/sdp` 或 `/dev/xvdf`–`/dev/xvdp`，不可重複）、`size`（必填，GiB，1–16384 的整數）、`type`（預設 `gp3`，可為 `gp3`、`gp2`、`io1`、`io2`、`st1`、`sc1`）、`kms_key_arn`（預設 `null`，用帳號預設的 EBS key；不收 alias）。 |
| `user_data` | `string` | `null` | 否 | 第一次開機執行的 cloud-init 或 shell script，上限 16384 bytes。以明文存在 state，也看得到在 EC2 console，不要放 secret：看起來像 secret 的明文值或私鑰會被擋下。 |
| `disable_api_termination` | `bool` | `true` | 否 | 終止保護。`terraform destroy` 前要先關掉。 |
| `sns_topic_arns` | `list(string)` | `[]` | 否 | `StatusCheckFailed_System` 告警（alarm 與 OK）的 SNS topic ARN，最多 4 個，因為告警還帶一個 recover action。空 list 時不建告警；這是 repo「告警必須有 SNS topic」慣例的唯一例外（D16）。 |
| `tags` | `map(string)` | `{}` | 否 | instance、volume 與告警的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `instance_id` | instance ID，`aws ssm start-session` 的 target。 |
| `private_ip` | instance 的私有 IP。 |
| `ami_id` | 有給 `ami_id` 時就是它，否則是最近一次 plan 時查到的最新 AMI。因為 `ignore_changes = [ami]`，不一定是這台實際在用的。 |
| `alarm_arns` | 告警名稱對應 ARN 的 map，key 是 `status_check_failed_system`；`sns_topic_arns` 為空時是空 map。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/ec2-instance
```
