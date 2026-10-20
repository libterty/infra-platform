---
status: "accepted"
date: 2026-10-14
decision-makers: platform team
outcome: "stack 之間的值只經 SSM Parameter Store 傳遞，路徑 `/<project>/<env>/<stack>/<key>`，只有一棵樹；寫入只能透過 `ssm-publish` module，讀取用 `data.aws_ssm_parameter` 的 `insecure_value`。不使用 `terraform_remote_state`。secret 的值不進 SSM，只放 ARN。"
notes: "validate.sh 第一版只靜態檢查兩條（S2：只有 ssm-publish 可宣告 aws_ssm_parameter；S3：ssm-inputs.tf 不讀 .value）。「讀的 key 必須是更早的 stack 發布的」不做，靠各 stack 的測試與合約表補位。SSM 不收空字串，可有可無的值要包成 JSON。"
---

# 跨 stack 的值只經 SSM 傳遞

## Context and Problem Statement

範本拆成 8 個 stack（見 [ADR-0002](./0002-split-state-by-owner-and-change-rate.md)），下游需要上游的輸出：VPC id、subnet、security group、secret ARN、資料庫端點等。Terraform 有兩種常見做法：用 `terraform_remote_state` 讀對方的 state，或讀雙方約定好的外部儲存。

客戶自管模式下，網路、資料庫、IAM 可能是客戶用他們自己的方式建的，不在我們的 state 裡。問題是：**stack 之間用什麼介面傳值，才能讓「上游由我們建」跟「上游由客戶建」對下游看起來一樣？**

參考專案也用 SSM 傳值；這份 ADR 把決定與理由記下來。

## Decision Drivers

* 客戶自管的資源不在我們的 state，介面不能依賴 state 檔。
* 下游不用知道上游是誰建的、用什麼工具建的。
* 不讓下游取得上游 state 的讀取權限（state 內含敏感值與全部資源細節）。
* 寫入方式要能用靜態檢查強制，不靠審查。

## Considered Options

* 只經 SSM Parameter Store，路徑與型別有合約
* `terraform_remote_state`
* 直接在 tfvars 複製貼上上游的值

## Decision Outcome

Chosen option: 「只經 SSM Parameter Store」，因為 SSM 是我們跟客戶都能接的介面：客戶自管某個 stack 時，只要照合約表把 key 發布到同一個路徑，下游不用改。

合約的核心規則：

| 規則 | 內容 |
|---|---|
| 路徑 | `/<project>/<env>/<stack>/<key>`；只有一棵樹 |
| key 命名 | snake_case；ARN 結尾 `_arn`、id 結尾 `_id`；服務名稱裡的 `-` 轉 `_` |
| 型別 | 純量用 `String`；清單用 `StringList`；多欄位或條件值用 `String` 裝 JSON |
| 條件值 | SSM 不收空字串，可有可無的值包成 JSON：`{"enabled":false}` |
| 單一決定點 | 兩個 stack 都要知道的開關，只由上游一個 stack 決定並發布，下游讀 |
| secret | 不進 SSM，只放 ARN，值在 Secrets Manager |
| 寫入 | 只能透過 `ssm-publish`，其他地方不得宣告 `aws_ssm_parameter` |
| 讀取 | `data "aws_ssm_parameter"` 加 `for_each`，讀 `insecure_value`；key 清單寫在 `ssm-inputs.tf` |
| 方向 | 只能讀 apply 順序更早的 stack 發布的 key |

### Consequences

* Good: 客戶自管任何一個 stack 時，下游程式不用改。
* Good: 下游不需要上游 state 的讀取權限。
* Bad: 多一層 SSM 參數要維護；`aws_ssm_parameter` 的 `value` 會進 state，所以 secret 值絕不放進去。
* Bad: SSM 不收空字串，可有可無的值要包 JSON，讀取端要 `jsondecode()`。
* Bad: 「方向」那條規則第一版沒有自動檢查。用 awk 這類文字工具解析 HCL，格式一變就誤判；檢查腳本沒接進 CI 也等於沒在跑。第一版靠兩件事補位：各 stack 的測試鎖住讀取清單；`infra/README.md` 的合約表標明每個 key 誰寫誰讀，PR 審查時對照。

### Confirmation

`scripts/validate.sh` 檢查下面兩條，並接進 CI：

* S2：只有 `modules/ssm-publish/` 可以宣告 `resource "aws_ssm_parameter"`。
* S3：範本的 `ssm-inputs.tf` 不得讀 `.value`，只能讀 `insecure_value`。

## Pros and Cons of the Options

### 只經 SSM Parameter Store

* Good: 客戶自管的資源也能發布；解耦；不需要 state 讀取權限。
* Bad: 多一層參數；型別只有字串，要自己約定 JSON 格式。

### `terraform_remote_state`

* Good: 原生、不用多一層參數，型別完整（list、object 直接傳）。
* Bad: 客戶自管的資源不在我們的 state 裡，讀不到。
* Bad: 下游要有上游 state bucket 的讀取權限，等於看得到整份 state。
* Bad: 兩份 state 的 backend 設定要互相知道。

### 在 tfvars 複製貼上

* Good: 最簡單，沒有依賴。
* Bad: 上游改了值，下游不會知道；一定會漂移。

## More Information

* 設計文件：[`docs/design/v1/design-docs.md`](../design/v1/design-docs.md) §5.6，含合約表與 `database` 的 JSON 欄位。
* 第三條檢查之後由 example2 的 `check-ssm-contract.sh` 實作，`scripts/validate.sh` 會呼叫它（見 [`docs/design/v2/design-docs.md`](../design/v2/design-docs.md) §5.5、§6）。
