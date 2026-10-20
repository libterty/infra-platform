# ec2-bastion

一台只能用 SSM Session Manager 進去的 bastion EC2：沒有 SSH key、沒有 public IP、強制 IMDSv2、root volume 加密。用來從內網連 RDS、ElastiCache 等資源（搭配 Session Manager 的 port forwarding）。

## 用法

```hcl
module "bastion" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ec2-bastion?ref=ec2-bastion-v0.1.0"

  name                  = "alpha-dev-bastion"
  subnet_id             = module.vpc.private_subnet_ids[0]
  security_group_ids    = [module.bastion_sg.id]
  instance_profile_name = module.bastion_role.instance_profile_name

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

- **沒有 `key_name`，也沒有 SSH。** 進去的唯一方式是 Session Manager，所以 `instance_profile_name` 必填，instance profile 要帶 `AmazonSSMManagedInstanceCore` 的權限（用 `iam-role` 建），subnet 要能連到 SSM endpoint（NAT，或 `ssm`、`ssmmessages`、`ec2messages` 的 VPC endpoint）。
- **固定的安全設定，沒有開關**：IMDSv2 必須、hop limit 1、不配 public IP、root volume 加密。`associate_public_ip_address` 明確寫 `false`，subnet 即使開了 auto-assign public IP 也不會生效。
- root volume 用帳號預設的 EBS KMS key 加密；要換成自管 key 目前不支援。
- AMI 是 Amazon Linux 2023 最新版（依 `architecture`）。**`ignore_changes = [ami]`**：之後出了新 AMI，既有的 bastion 不會被取代，要更新就用 `terraform apply -replace=module.bastion.aws_instance.this`。`ami_id` 輸出是目前查到的最新 AMI，不一定是這台實際在用的那個。
- `instance_type` 必須跟 `architecture` 搭配：Graviton（`t4g`、`m7g`、`c6gn` 等）用 `arm64`，其他用 `x86_64`。判斷方式是看家族名稱，plan 時擋下不搭的組合；舊的 `a1` 家族是 arm64 但不會被認出來，不支援。
- `root_volume_size` 最小 8（AMI 快照大小），必須是整數 GiB。
- security group 由 `security-group` module 建；這個 module 不建 security group、IAM、Elastic IP。

## 刻意不做

- SSH key、public IP、IMDSv1。
- user data、額外的 EBS volume、自訂 KMS key。
- IAM role 與 instance profile（用 `iam-role` 建）、security group（用 `security-group` 建）。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | instance 名稱，也是 `Name` tag；小寫英數字與連字號 |
| `subnet_id` | `string` | 無 | 是 | 放 instance 的 private subnet |
| `security_group_ids` | `list(string)` | 無 | 是 | 至少一個 security group |
| `instance_profile_name` | `string` | 無 | 是 | 帶 SSM Session Manager 權限的 instance profile |
| `instance_type` | `string` | `"t4g.nano"` | 否 | 必須跟 `architecture` 搭配 |
| `architecture` | `string` | `"arm64"` | 否 | `arm64` 或 `x86_64` |
| `root_volume_size` | `number` | `8` | 否 | root volume GiB，8 到 16384 的整數 |
| `tags` | `map(string)` | `{}` | 否 | instance 與 root volume 的 tag；`Name` 由 module 加上 |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `instance_id` | `string` | instance ID，`aws ssm start-session` 的 target |
| `private_ip` | `string` | 私有 IP |
| `ami_id` | `string` | 目前查到的最新 AMI；因為 `ignore_changes = [ami]`，不一定是這台實際在用的 |

## 測試

```bash
scripts/validate.sh modules/ec2-bastion
```
