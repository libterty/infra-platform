# ssm-read

跟 [`ssm-publish`](../ssm-publish/README.md) 配對的讀取 module。給 `<stack>/<key>` 清單，回傳字串與清單。各 stack 的 `ssm-inputs.tf` 都呼叫它，不用再各自寫 `data "aws_ssm_parameter"` 與 `split()`。

這是專案範本裡唯一可以宣告 `data "aws_ssm_parameter"` 的地方，而且檔案裡不得出現 `.value`（由 `scripts/validate.sh` 的 S3 規則強制檢查）。

## 用法

```hcl
module "in" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ssm-read?ref=ssm-read-v0.1.0"

  ssm_prefix = "/alpha/dev"

  strings = {
    vpc_id   = "network/vpc_id"
    database = "data/database"
  }

  lists = {
    subnet_ids_app = "network/subnet_ids_app"
  }
}

locals {
  vpc_id   = module.in.strings["vpc_id"]
  database = jsondecode(module.in.strings["database"])
  subnets  = module.in.lists["subnet_ids_app"]
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。左邊是本地名稱，右邊是 `<stack>/<key>`，實際讀的參數是 `<ssm_prefix>/<stack>/<key>`。

## 行為

- 只讀 `insecure_value`，不讀 `value`。`ssm-publish` 寫入的都不是 secret，讀 `value` 會讓整條值被標成 sensitive。
- `lists` 的值以逗號切開，對應 `ssm-publish` 的逗號串接。
- 同一個 `<stack>/<key>` 出現在多個本地名稱（含 `strings` 與 `lists` 兩邊）時只讀一次。
- 兩個 map 都空時不讀任何參數。
- 參數不存在時 plan 會直接失敗，這是刻意的：上游還沒 apply 或客戶還沒發布時，不應該繼續規劃。
- JSON 值（例如 `database`）放在 `strings`，由呼叫端 `jsondecode()`；module 不猜哪些值是 JSON。

## 限制

- 不讀 `SecureString`，secret 走 Secrets Manager。
- 沒有預設值，缺 key 就是失敗。
- 不遞迴讀整個路徑（`aws_ssm_parameters_by_path` 會讓實際讀了哪些參數變得看不出來）。
- `<stack>/<key>` 的規則跟 `ssm-publish` 一致：stack 是小寫字母開頭、可含數字與連字號，key 是 snake_case。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `ssm_prefix` | `string` | 無 | 是 | `/<project>/<env>`，跟 `ssm-publish` 相同。 |
| `strings` | `map(string)` | `{}` | 否 | 本地名稱對應 `<stack>/<key>`，讀 `String` 參數。 |
| `lists` | `map(string)` | `{}` | 否 | 本地名稱對應 `<stack>/<key>`，讀 `StringList` 參數。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `strings` | `String` 參數的值，key 為本地名稱。 |
| `lists` | `StringList` 參數以逗號切開的清單，key 為本地名稱。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/ssm-read
```
