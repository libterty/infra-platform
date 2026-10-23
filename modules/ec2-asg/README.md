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

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | Auto Scaling group 與 launch template 名稱，也是每台 instance 的 `Name` tag。2–63 字元，限小寫英數字與連字號，字母開頭。 |
| `subnet_ids` | `list(string)` | 無 | 是 | ASG 啟動 instance 的 private subnet（`subnet-…` 格式），至少一個。instance 不會拿到 public IP。 |
| `security_group_ids` | `list(string)` | 無 | 是 | instance 的 security group（`sg-…` 格式），至少一個。 |
| `instance_profile_name` | `string` | 無 | 是 | instance 的 instance profile 名稱，1–128 字元（例如帶 SSM Session Manager 權限）。沒有 SSH key。 |
| `instance_types` | `list(string)` | 無 | 是 | instance type 清單，至少一個（例如 `t4g.small`），第一個是主要型號；其餘只當 spot override，所以只有設了 `spot` 才用得到。全部都要跟 `architecture` 搭配：Graviton 家族（`t4g`、`m7g`、`c6gn` 等）用 `arm64`，其他用 `x86_64`。 |
| `architecture` | `string` | `"arm64"` | 否 | `arm64` 或 `x86_64`，決定用哪個 Amazon Linux 2023 AMI。 |
| `ami_id` | `string` | `null` | 否 | instance 的 AMI（`ami-…` 格式）；`null` 時找依 `architecture` 的最新 Amazon Linux 2023，出了新 AMI 會透過 instance refresh 換上。 |
| `root_volume` | `object` | `{}` | 否 | root volume，一律是加密的 gp3。欄位：`size`（GiB，8–16384 的整數，預設 `20`；Amazon Linux 2023 快照是 8 GiB，所以最小 `8`）、`kms_key_arn`（KMS key ARN，不收 alias；預設 `null`，用帳號預設的 EBS key）。 |
| `user_data` | `string` | `null` | 否 | 第一次開機執行的 shell script。以明文存在 state 與 launch template，能讀 launch template 的人都看得到，不要放 secret，改在開機時從 Secrets Manager 讀。看起來像 secret 的明文值或私鑰會被擋下。 |
| `min_size` | `number` | 無 | 是 | 最少台數，不小於 0 的整數。 |
| `max_size` | `number` | 無 | 是 | 最多台數，不小於 0 的整數。 |
| `desired_capacity` | `number` | 無 | 是 | 建立時的台數，整數，`min_size <= desired_capacity <= max_size`。只在建立 ASG 時使用，之後的變更會被忽略，數量交給 scaling policy。 |
| `spot` | `object` | `null` | 否 | 搭配 spot 的 mixed instances policy；`null` 時全部 on-demand，不建 `mixed_instances_policy`。欄位：`on_demand_base_capacity`（不小於 0 的整數，預設 `1`）、`on_demand_percentage_above_base`（0–100，預設 `0`）、`allocation_strategy`（`price-capacity-optimized`（預設）、`capacity-optimized`、`capacity-optimized-prioritized`、`lowest-price`）。用預設值時保留 1 台 on-demand，其餘都是 spot。 |
| `target_group_arns` | `list(string)` | `[]` | 否 | 要把 instance 註冊進去的 target group ARN（ALB `target_type = instance`）。非空時 health check 類型改成 `ELB`。 |
| `health_check_grace_period` | `number` | `300` | 否 | instance 啟動後幾秒才開始算 health check，不小於 0 的整數。要比開機加 `user_data` 跑完的時間長。 |
| `instance_refresh` | `object` | `{}` | 否 | launch template 變更（例如新 AMI 或 `user_data`）時啟動的 rolling instance refresh。欄位：`min_healthy_percentage`（0–100，預設 `90`）。 |
| `cpu_target` | `number` | `null` | 否 | target tracking policy（`ASGAverageCPUUtilization`）的平均 CPU 目標百分比，大於 0、最多 100；`null` 時不建 scaling policy。 |
| `tags` | `map(string)` | `{}` | 否 | launch template 與每台 instance 的 tag（`propagate_at_launch`）；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `asg_name` | Auto Scaling group 名稱。 |
| `asg_arn` | Auto Scaling group ARN。 |
| `launch_template_id` | launch template ID。 |
| `launch_template_latest_version` | launch template 的最新版本，也就是 ASG 啟動機器用的版本。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/ec2-asg
```
