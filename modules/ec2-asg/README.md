# ec2-asg

一組 EC2 Auto Scaling group：launch template 加 ASG，機器掛了會自動補，可以掛 ALB 的 target group，可以用 CPU 做 target tracking。沒有 SSH key、沒有 public IP、強制 IMDSv2、root volume 加密。單台機器用 `ec2-bastion`（或 `ec2-instance`）。

## 用法

```hcl
module "web" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ec2-asg?ref=ec2-asg-v0.1.0"

  name                  = "alpha-dev-web"
  subnet_ids            = module.vpc.private_subnet_ids
  security_group_ids    = [module.web_sg.id]
  instance_profile_name = module.web_role.instance_profile_name
  instance_types        = ["t4g.small"]

  min_size         = 2
  desired_capacity = 2
  max_size         = 6

  cpu_target = 60

  tags = {
    Project = "alpha"
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

### 怎麼掛 ALB

`alb`（0.4.0 起）的 `target_groups` 可以設 `target_type = "instance"`，再把 target group 的 ARN 傳進來。`target_group_arns` 不是空的，`health_check_type` 就會自動變成 `ELB`，ALB 判定 unhealthy 的機器會被換掉。

```hcl
module "alb" {
  source = "git::https://github.com/<org>/<repo>.git//modules/alb?ref=alb-v0.4.0"
  # ...
  target_groups = {
    web = { port = 8080, target_type = "instance" }
  }
}

module "web" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ec2-asg?ref=ec2-asg-v0.1.0"
  # ...
  target_group_arns = [module.alb.target_group_arns["web"]]
}
```

上面 `alb` 的參數與輸出名稱請以 alb README 為準。ALB 的 security group 要允許連到 instance 的 port，這是 `security-group` module 的事。

## 注意

- **`user_data` 是明文。** 它會以明文存在 state 與 launch template 裡，能讀 launch template 的人都看得到。不要放 secret，要用就在開機時從 Secrets Manager 讀。名稱含 `SECRET`、`PASSWORD`、`PASSWD`、`TOKEN`、`API_KEY`（也含 `API-KEY`）、`PRIVATE_KEY`、`CREDENTIAL` 的變數或設定直接寫了明文值（例如 `DB_PASSWORD=hunter2`、`x-api-key: abc`），或內容含有私鑰（`-----BEGIN … PRIVATE KEY-----`），會在 plan 時被擋下（不分大小寫）。值是從變數或指令取得的不擋，例如 `PASSWORD=$(aws secretsmanager get-secret-value ...)`、`TOKEN=$(curl ...)`。
- **換 AMI 靠 instance refresh。** `ami_id = null` 時每次 plan 都會查最新的 Amazon Linux 2023，出了新 AMI，launch template 會多一個版本，ASG 改用新版本並啟動 rolling instance refresh（`min_healthy_percentage` 預設 90）。launch template 其他欄位（`user_data`、instance type、root volume 等）改了也一樣。要固定 AMI 就傳 `ami_id`。refresh 期間 ASG 會逐批換機器，`min_size` 太小或 `health_check_grace_period` 太短都會讓換機過程出問題。
- **`desired_capacity` 只在建立時用。** 之後的變更會被 `ignore_changes` 忽略，數量交給 scaling policy（`cpu_target`）或手動調整管理。要改常態數量請改 `min_size`／`max_size`。
- **`spot = {}` 會保留 1 台 on-demand，其餘都用 spot。** 預設是 `on_demand_base_capacity = 1`、`on_demand_percentage_above_base = 0`、`allocation_strategy = "price-capacity-optimized"`。要多留 on-demand，就調高這兩個值。
- **`instance_types` 只有設了 `spot` 才會全部用到。** `spot = null` 時沒有 mixed instances policy，只用第一個型號，其餘的被忽略。所有型號都必須跟 `architecture` 搭配：Graviton（`t4g`、`m7g`、`c6gn` 等）用 `arm64`，其他用 `x86_64`。module 看家族名稱判斷，舊的 `a1` 家族不會被認出來。
- **固定的安全設定，沒有開關**：IMDSv2 必須、hop limit 1、不配 public IP（明確寫 `false`，subnet 開了 auto-assign 也不會生效）、root volume 是加密的 gp3。沒有 `key_name`，要進機器走 Session Manager，instance profile 要帶 SSM 權限、subnet 要連得到 SSM endpoint。
- root volume 預設用帳號的 EBS KMS key，要換就設 `root_volume.kms_key_arn`（必須是 key ARN，不接受 alias）。
- `health_check_grace_period` 預設 300 秒，要比開機加 `user_data` 跑完的時間長。
- tags 會帶到每台 instance 與 volume（`propagate_at_launch`），`Name` 由 module 加上。

## 刻意不做

- SSH key、public IP、IMDSv1。
- IAM role 與 instance profile（用 `iam-role` 建）、security group（用 `security-group` 建）。
- step scaling、scheduled action、warm pool、lifecycle hook、額外的 EBS volume。
- 讀 SSM 參數取得 AMI（只有 `ssm-read` 能讀 SSM 參數，所以用 `data "aws_ami"`）。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | ASG 與 launch template 名稱，也是每台 instance 的 `Name` tag；小寫英數字與連字號 |
| `subnet_ids` | `list(string)` | 無 | 是 | 放 instance 的 private subnet，至少一個 |
| `security_group_ids` | `list(string)` | 無 | 是 | 至少一個 security group |
| `instance_profile_name` | `string` | 無 | 是 | instance profile 名稱 |
| `instance_types` | `list(string)` | 無 | 是 | 至少一個，第一個是主要型號；都要跟 `architecture` 搭配 |
| `architecture` | `string` | `"arm64"` | 否 | `arm64` 或 `x86_64` |
| `ami_id` | `string` | `null` | 否 | `null` 找最新的 Amazon Linux 2023 |
| `root_volume` | `object({ size, kms_key_arn })` | `{ size = 20, kms_key_arn = null }` | 否 | root volume GiB（8 到 16384 的整數）與 KMS key ARN |
| `user_data` | `string` | `null` | 否 | 開機腳本；明文，看起來像 secret 的內容會被拒 |
| `min_size` | `number` | 無 | 是 | 最少台數 |
| `max_size` | `number` | 無 | 是 | 最多台數 |
| `desired_capacity` | `number` | 無 | 是 | 建立時的台數，`min_size <= desired_capacity <= max_size`；之後被忽略 |
| `spot` | `object({ on_demand_base_capacity, on_demand_percentage_above_base, allocation_strategy })` | `null` | 否 | `null` 全 on-demand 且不建 mixed instances policy；欄位預設 `1`、`0`、`"price-capacity-optimized"` |
| `target_group_arns` | `list(string)` | `[]` | 否 | 非空時 health check 用 `ELB` |
| `health_check_grace_period` | `number` | `300` | 否 | 秒 |
| `instance_refresh` | `object({ min_healthy_percentage })` | `{ min_healthy_percentage = 90 }` | 否 | rolling refresh 的最低健康比例，0 到 100 |
| `cpu_target` | `number` | `null` | 否 | 有值才建 `ASGAverageCPUUtilization` target tracking policy |
| `tags` | `map(string)` | `{}` | 否 | launch template 與每台 instance 的 tag；`Name` 由 module 加上 |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `asg_name` | `string` | ASG 名稱 |
| `asg_arn` | `string` | ASG ARN |
| `launch_template_id` | `string` | launch template ID |
| `launch_template_latest_version` | `string` | launch template 最新版本，ASG 啟動機器用的版本 |

## 測試

```bash
scripts/validate.sh modules/ec2-asg
```
