# lb-traffic-breaker

ALB 或 NLB 做加權分流（金絲雀）時的斷路器：新系統出問題，就自動把流量全部切回舊系統。

module 只建 CloudWatch alarm，並輸出 Lambda 需要的設定與呼叫授權。Lambda 本身（`lambda-function`）與它的 role（`iam-role`）由呼叫端建，module 不建任何 Lambda、IAM。Lambda 的程式碼與 Dockerfile 放在 [`lambda/`](./lambda)，映像要自己 build、推到 ECR。

## 運作方式

1. `breakers` 的每個 key 是一條「新系統出問題就切回舊系統」的規則，指向一個 listener（預設 action）或一條 listener rule。
2. module 為每個 breaker 建 alarm，名稱 `<name>-<key>-<signal>`：
   - `error-rate`（只有 ALB）：新系統 target group 的 5xx 錯誤率，`HTTPCode_Target_5XX_Count ÷ RequestCount × 100`，超過 `error_rate_percent`（預設 5）。該期請求數低於 `min_requests`（預設 50）就不算。缺資料視為 `notBreaching`。
   - `healthy-hosts`：新系統 target group 的 `HealthyHostCount` 低於 `min_healthy_hosts`（預設 1）。缺資料視為 `breaching`（沒有 target 或不回報，視同不健康）。
   - `custom`（可選）：`custom_metric` 指定的應用程式指標。缺資料視為 `notBreaching`。
3. alarm 進入 ALARM 時，CloudWatch 以非同步方式呼叫 Lambda，同時通知 SNS。恢復（OK）時只通知 SNS，不呼叫 Lambda。
4. Lambda 依 `BREAKER_CONFIG` 找到該 alarm 對應的 listener 或 rule，`DescribeListeners` 或 `DescribeRules` 取得目前的 action，把 forward 裡 stable target group 的權重保持（若為 0 則設成 1）、其他 target group 設成 0，保留 stickiness 與其他 action，再用 `ModifyListener` 或 `ModifyRule` 帶完整 action 清單寫回，最後在該 listener 或 rule 加 tag `traffic-breaker/tripped = <alarm 名稱>`。
5. 冪等：已經只有 stable 有權重就直接結束，不重複修改。
6. Lambda 失敗會記 log 並拋出例外（Lambda 會依非同步呼叫的設定重試）；alarm 同時通知 SNS，人會知道。

`lambda_permissions` 的 alarm ARN 是由名稱加上目前的 partition、region、帳號組出來的，不是取自 alarm resource。所以可以把它傳給 `lambda-function`，而 `lambda-function` 的 `function_arn` 又傳回本 module，不會形成循環。

## 用法

下面是完整組裝：`iam-role`（Lambda 的 role）、`lambda-function`、本 module。`alb` 0.4.0 以上才有 `listener_arns` 與 `listener_rule_arns` 輸出。

```hcl
locals {
  # The only ELB resources the Lambda may change.
  breaker_resource_arns = [
    module.alb.listener_arns["https"],
    module.alb.listener_rule_arns["api"],
  ]
}

module "breaker_role" {
  source = "git::https://github.com/<org>/<repo>.git//modules/iam-role?ref=iam-role-v0.3.0"

  name        = "dev-web-breaker"
  description = "Traffic breaker Lambda"

  trust = {
    service_principals = ["lambda.amazonaws.com"]
    source_account     = "111111111111"
  }

  inline_policies = {
    breaker = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["elasticloadbalancing:ModifyListener", "elasticloadbalancing:ModifyRule", "elasticloadbalancing:AddTags"]
          Resource = local.breaker_resource_arns
        },
        {
          # Describe actions do not support resource-level permissions.
          Effect   = "Allow"
          Action   = ["elasticloadbalancing:DescribeListeners", "elasticloadbalancing:DescribeRules"]
          Resource = "*"
        },
        {
          # lambda-function creates the log group; the role only writes to it.
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/lambda/dev-web-breaker:*"
        },
      ]
    })
  }
}

module "breaker_function" {
  source = "git::https://github.com/<org>/<repo>.git//modules/lambda-function?ref=lambda-function-v0.1.0"

  name      = "dev-web-breaker"
  image_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/dev-web-breaker:v0.1.0"
  role_arn  = module.breaker_role.arn

  environment = {
    BREAKER_CONFIG = module.breaker.lambda_config_json
  }

  permissions = module.breaker.lambda_permissions
}

module "breaker" {
  source = "git::https://github.com/<org>/<repo>.git//modules/lb-traffic-breaker?ref=lb-traffic-breaker-v0.1.0"

  name                     = "dev-web"
  load_balancer_type       = "application"
  load_balancer_arn_suffix = module.alb.alb_arn_suffix
  lambda_function_arn      = module.breaker_function.function_arn
  sns_topic_arns           = [module.alarm_topic.topic_arn]

  breakers = {
    api = {
      rule_arn                       = module.alb.listener_rule_arns["api"]
      stable_target_group_arn        = module.alb.target_group_arns["old"]
      canary_target_group_arn_suffix = module.alb.target_group_arn_suffixes["new"]
    }
  }
}
```

- `lambda-function` 預設 `architectures = ["arm64"]`，映像也要用 arm64 build（見下面）。
- `iam-role` 的 inline policy 不接受 `*` 或 `service:*` 的 Allow action，上面都是明確的 action。
- `breaker_resource_arns` 只列 `breakers` 用到的 listener 與 rule。Lambda 只會碰 `BREAKER_CONFIG` 裡列出的 ARN，IAM 再限一次。
- 完整的單一 module 範例見 [`examples/basic/`](./examples/basic/main.tf)。

## ALB 與 NLB 的差異

| 項目 | ALB | NLB |
|---|---|---|
| 觸發訊號 | 新系統 target group 的 5xx 錯誤率（請求數低於 `min_requests` 不算）、`HealthyHostCount < min_healthy_hosts` | `HealthyHostCount < min_healthy_hosts`、可選的 `custom_metric` |
| 看得到「連得上但回錯」 | 看得到 | 看不到，除非應用程式自己發指標（`custom_metric`） |
| 切回後的生效 | 下一個請求就照新權重 | 只影響新連線，最多約 3 分鐘；既有的長連線不會被移走 |
| 能改的位置 | listener 預設 action（`listener_arn`）或 rule（`rule_arn`） | listener 預設 action（只能 `listener_arn`） |
| `error_rate_percent`、`min_requests` | 可設，預設 5、50 | 不能設，設了會被 validation 擋下 |

NLB 的 `healthy-hosts` 還有一個要注意的地方：每個 AZ 都要有新系統的 target，否則該 AZ 沒有健康 target 時會一直觸發。

## 注意

- **只能用在 Terraform 擁有的 listener 與 rule。** 如果 listener 或 rule 是 AWS Load Balancer Controller 管的（Ingress、Service），controller 之後 reconcile 會把 Lambda 的修改改回去，斷路器形同無效（R2）。
- **斷路器不會自動回復，而且下次 `apply` 會把權重改回 tfvars 的值（R1）。** 斷路器觸發後，先照下面的處理流程改 tfvars，才可以再 `apply`；`apply` 前要看 plan 有沒有改到 listener 或 rule 的權重。module 不加 `ignore_changes`，否則 tfvars 改權重也不會生效。
- **Lambda 失敗時權重沒有改到，alarm 仍然是 ALARM，不會再次觸發 Lambda（R11）。** 所以 alarm 一定同時通知 SNS；收到通知後要去看 Lambda 的 log（`/aws/lambda/<function name>`），必要時手動改權重。
- **映像 tag 要跟 module 版本對齊（R12）。** `BREAKER_CONFIG` 帶 `schema_version`，Lambda 遇到不認得的版本會直接失敗並記 log。升級 module 時，先 build、推新版映像，再改 `image_uri` 與 module 版本一起 apply。
- `breakers` 的 key 只能小寫字母、數字、連字號（最長 20 字元），因為它會變成 alarm 名稱的一部分。
- `lambda_function_arn` 不可以帶 version 或 alias：呼叫授權是授權在 function 本身。
- stable 跟 canary 不能是同一個 target group；listener 或 rule 必須屬於 `load_balancer_arn_suffix` 指的那個 load balancer。
- listener 或 rule 的 forward 裡必須有 stable target group，而且至少有兩個 target group 才有權重可以調。只有單一 target group 的 forward 不會被改動；單一 target group 但不是 stable 時 Lambda 會失敗，不會亂改。
- rule 若含 `authenticate-oidc` action，Lambda 把 describe 的結果原樣寫回，API 是否要求重送 client secret 沒有驗證過（未確認），不要用在這種 rule 上。
- `period` 是 60 的倍數、最小 60；`period × evaluation_periods` 不能超過 86400 秒。預設 3 期中 2 期超標就觸發，約 2 到 3 分鐘。
- 不加 `custom_metric` 的 ALB 有兩條 alarm，加了是三條；NLB 是一條，加了是兩條。
- `sns_topic_arns` 必填，`alarm_actions` 是 Lambda 加 SNS，`ok_actions` 只有 SNS。

## 斷路器觸發後的處理流程

1. SNS 通知到人，確認 Lambda 已經把權重改成舊系統 100%：listener 或 rule 上有 `traffic-breaker/tripped` tag，權重只剩 stable。
2. 先把 tfvars 裡那條規則的權重改成舊系統 100%、新系統 0，再 `apply`。這一步沒做，下次任何人 `apply` 都會把新系統的權重改回來。
3. 修好新系統後，照正常流程逐步調回權重，每一步都是改 tfvars 再 `apply`。
4. 確認 alarm 回到 OK，再移除 tag。

## Lambda 映像的 build 與推送

repo 只提供程式碼與 Dockerfile（[`lambda/`](./lambda)），CI 不 build 映像。程式碼分兩層：`breaker.py` 是只用標準函式庫的純函式，`handler.py` 是呼叫 boto3 的薄殼（boto3 用 Lambda runtime 內建的）。

單元測試（不需要 boto3、不連 AWS）：

```bash
python3 -I -m unittest discover -s modules/lb-traffic-breaker/lambda -t modules/lb-traffic-breaker/lambda -v
```

build 並推到 ECR（先用 `ecr-repository` module 建 repository；tag 跟 module 版本一致，不能用 `latest`，`lambda-function` 會擋）：

```bash
ACCOUNT=111111111111
REGION=ap-northeast-1
REPO=dev-web-breaker
VERSION=v0.1.0   # 跟 lb-traffic-breaker module 的版本對齊

aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

# --provenance=false: Lambda does not accept the attestation manifest buildx adds by default.
docker buildx build --platform linux/arm64 --provenance=false \
  -t "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/$REPO:$VERSION" \
  --push modules/lb-traffic-breaker/lambda
```

- 平台要跟 `lambda-function` 的 `architectures` 一致（預設 arm64）。要用 x86_64 就改 `--platform linux/amd64`，同時設 `architectures = ["x86_64"]`。
- Dockerfile 的 base image 是 `public.ecr.aws/lambda/python:3.14`，並且固定 sha256 digest。要換版本時 tag 與 digest 一起換，並重新確認 Lambda 支援該 runtime。
- 推完後把 `image_uri` 設成這個 tag，由 Terraform 管。

`BREAKER_CONFIG` 的格式（`lambda_config_json` 的輸出）：

```json
{
  "schema_version": 1,
  "alarms": {
    "dev-web-api-error-rate": {
      "rule_arn": "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbb",
      "stable_target_group_arn": "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
    }
  }
}
```

每個 alarm 名稱有 `listener_arn` 或 `rule_arn` 其中一個，加上 `stable_target_group_arn`。

CloudWatch 呼叫 Lambda 的 event 取自官方文件，Lambda 只讀 `alarmData.alarmName` 與 `alarmData.state.value`，只處理 `ALARM`。

## 刻意不做

- 建 Lambda、IAM role（用 `lambda-function`、`iam-role`）。
- 自動回復權重；回復一律由人改 tfvars 再 `apply`。
- 改 AWS Load Balancer Controller 管的 listener 或 rule。
- NLB 的 HTTP 錯誤偵測（NLB 沒有這類指標）。
- 在 CI build Docker 映像。

## 未確認

- 從 alarm 進入 ALARM 到權重生效的實際時間，要在真實環境量測。
- NLB 改權重後約 3 分鐘才生效、只影響新連線，是 AWS blog 的說法。
- `ModifyListener`、`ModifyRule`、`AddTags` 的 resource-level 限制在真實環境是否如上面的 policy 所寫。
- 含 `authenticate-oidc` 的 action 能否原樣寫回。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | 名稱前綴，小寫英數字與連字號，最長 60 字元 |
| `load_balancer_type` | `string` | 無 | 是 | `application` 或 `network` |
| `load_balancer_arn_suffix` | `string` | 無 | 是 | load balancer 的 `arn_suffix`，`app/...` 或 `net/...` 要跟類型一致 |
| `breakers` | `map(object)` | 無 | 是 | 見下表 |
| `lambda_function_arn` | `string` | 無 | 是 | 斷路器 Lambda 的 ARN，不帶 version 或 alias |
| `sns_topic_arns` | `list(string)` | 無 | 是 | 至少一個，同時用於 `alarm_actions` 與 `ok_actions` |
| `tags` | `map(string)` | `{}` | 否 | alarm 的 tag；`Name` 由 module 加上 |

`breakers` 每個項目：

| 欄位 | 預設 | 說明 |
|---|---|---|
| `listener_arn`、`rule_arn` | `null` | 二選一；NLB 只能 `listener_arn` |
| `stable_target_group_arn` | 必填 | 舊系統的 target group ARN，切回後留下的那個 |
| `canary_target_group_arn_suffix` | 必填 | 新系統的 target group `arn_suffix`（`targetgroup/<name>/<id>`） |
| `error_rate_percent` | ALB 為 `5` | 只有 ALB 能設，`0 < x <= 100` |
| `min_requests` | ALB 為 `50` | 只有 ALB 能設，至少 1 |
| `min_healthy_hosts` | `1` | 至少 1 |
| `period` | `60` | 60 的倍數 |
| `evaluation_periods` | `3` | 至少 1 |
| `datapoints_to_alarm` | `2` | 1 到 `evaluation_periods` |
| `custom_metric` | `null` | `namespace`、`metric_name`、`threshold` 必填；`dimensions`（`{}`）、`statistic`（`Average`）、`comparison_operator`（`GreaterThanThreshold`） |

## 輸出

| 名稱 | 說明 |
|---|---|
| `alarm_arns` | alarm ARN，key 是 `<breaker key>-<signal>` |
| `alarm_names` | alarm 名稱，key 同上；plan 時就已知 |
| `lambda_config_json` | 給 Lambda 環境變數 `BREAKER_CONFIG` |
| `lambda_permissions` | 直接傳給 `lambda-function` 的 `permissions`：principal `lambda.alarms.cloudwatch.amazonaws.com`，`source_arn` 是各 alarm 的 ARN，`source_account` 是目前帳號 |
