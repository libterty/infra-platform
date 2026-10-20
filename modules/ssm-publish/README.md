# ssm-publish

把一個 stack 要給下游的值寫進 SSM Parameter Store。路徑規則是 `/<project>/<env>/<stack>/<key>`。

這是專案範本裡唯一可以宣告 `aws_ssm_parameter` 的地方（由 `scripts/validate.sh` 的 S2 規則強制檢查）。

## 用法

```hcl
module "publish" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ssm-publish?ref=ssm-publish-v0.1.0"

  ssm_prefix = "/alpha/dev"
  stack      = "network"

  strings = {
    vpc_id = module.vpc.vpc_id
  }

  lists = {
    subnet_ids_private = module.vpc.private_subnet_ids
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

上例會建立：

| 參數名稱 | 型別 |
|---|---|
| `/alpha/dev/network/vpc_id` | `String` |
| `/alpha/dev/network/subnet_ids_private` | `StringList`，值以逗號串接 |

## 讀取端怎麼寫

這個 repo 不提供讀取用的 module。讀取就是一個 `data "aws_ssm_parameter"` 加 `for_each`：

```hcl
data "aws_ssm_parameter" "network" {
  for_each = toset(["vpc_id", "subnet_ids_private"])

  name = "${local.ssm_prefix}/network/${each.key}"
}

locals {
  vpc_id             = data.aws_ssm_parameter.network["vpc_id"].insecure_value
  subnet_ids_private = split(",", data.aws_ssm_parameter.network["subnet_ids_private"].insecure_value)
}
```

讀 `insecure_value`，不讀 `value`。這個 module 寫入的都不是 secret，讀 `value` 會讓整條值被標成 sensitive。

## 限制

- 只支援 `String` 與 `StringList`，不支援 `SecureString`。secret 走 Secrets Manager。
- SSM 不收空字串。可有可無的值包成 JSON，例如 `jsonencode({ enabled = false })`。
- 單一值最長 4096 字元（Standard tier）。
- list 的元素不能含逗號，否則讀取端用 `split(",", ...)` 會切錯。
- `strings` 與 `lists` 的 key 不能重複，因為兩者會寫到同一個路徑。
- `ssm_prefix` 的 `<env>` 段只能是小寫字母與數字，不能有連字號。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `ssm_prefix` | `string` | 無 | 是 | `/<project>/<env>`；`<project>` 小寫字母開頭，可含數字與連字號，`<env>` 小寫字母開頭，可含數字 |
| `stack` | `string` | 無 | 是 | 產出值的 stack 名稱，小寫字母開頭，可含數字與連字號 |
| `strings` | `map(string)` | `{}` | 否 | 以 `String` 發布的值；key 為 snake_case，值 1–4096 字元 |
| `lists` | `map(list(string))` | `{}` | 否 | 以 `StringList` 發布的值；key 為 snake_case，list 不可為空，元素不可為空字串或含逗號 |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `names` | `map(string)` | 參數名稱，key 為參數 key |
| `arns` | `map(string)` | 參數 ARN，key 為參數 key；apply 前是 unknown |

## 測試

```bash
scripts/validate.sh modules/ssm-publish
```
