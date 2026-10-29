# securityhub

在一個 region 啟用 Security Hub CSPM，訂閱 AWS Foundational Security Best Practices（FSBP）與 CIS AWS Foundations Benchmark。可選擇另建跨 region 的 finding aggregator，或在委派管理帳號設定 organization 的自動啟用。

## 用法

```hcl
module "securityhub" {
  source = "git::https://github.com/<org>/<repo>.git//modules/securityhub?ref=securityhub-v0.1.0"

  standards = ["fsbp", "cis"]
}
```

Organizations 模式（在資安帳號，也就是 Security Hub 的委派管理帳號）：

```hcl
module "securityhub" {
  source = "git::https://github.com/<org>/<repo>.git//modules/securityhub?ref=securityhub-v0.1.0"

  finding_aggregator = { linking_mode = "ALL_REGIONS" }

  organization = {
    auto_enable           = true
    auto_enable_standards = "NONE"
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| AWS 預設標準 | `enable_default_standards = false`；訂閱哪些標準只由 `standards` 決定 |
| 標準 ARN | `fsbp` → `arn:<partition>:securityhub:<region>::standards/aws-foundational-security-best-practices/v/1.0.0`；`cis` → `arn:<partition>:securityhub:<region>::standards/cis-aws-foundations-benchmark/v/5.0.0` |
| control finding | `control_finding_generator` 預設 `SECURITY_CONTROL`（同一個 control 只出一筆 finding） |
| organization | local configuration（`configuration_type = "LOCAL"`） |

## 注意

- **Security Hub CSPM 與新版 Security Hub**：AWS 在 2025 年把原本的 Security Hub 改名為 Security Hub CSPM，另推新版 Security Hub。FSBP 與 CIS 這些標準屬於 CSPM；這個 module 用的 `aws_securityhub_account` 管的就是 CSPM。新版 Security Hub（provider 的 `*_v2` resource）可以同時開，這個 module 不管。
- **CIS 用 v5.0.0**：Security Hub CSPM 支援 CIS v5.0.0、v3.0.0、v1.4.0、v1.2.0，AWS 建議用最新的 v5.0.0。從舊版升級時先開新版再關舊版，中間才不會沒有檢查。
- **大部分 control 靠 AWS Config 評估**：這個 region 要先有 Config recorder（`config-recorder`），否則 control 會是沒有資料的狀態。
- **其他 region**：Security Hub 是 regional 服務，FSBP 與 CIS 也會對沒開 Security Hub 的 region 出 finding。要涵蓋其他 region 就用 `region` 多呼叫一次；`finding_aggregator` 只建在彙整用的那個 region。
- **既有帳號已經啟用 Security Hub** 時 apply 會失敗，先用 `terraform import` 匯入 `aws_securityhub_account`。
- **Organizations 模式**：`organization` 只在委派管理帳號給；委派本身由 `organization-delegated-admin` 在管理帳號做。local configuration 下，管理員不能替成員帳號訂閱標準：`auto_enable_standards = "DEFAULT"` 只會幫新成員開 AWS 的預設標準（FSBP 與 CIS v1.2.0），要讓成員用 CIS v5.0.0 得在成員帳號呼叫這個 module，或改用 central configuration（不在這個 module）。
- **停用會刪 finding**：destroy 這個 module 會停用 Security Hub，既有 finding 一併刪除。
- 高嚴重度 finding 的通知用 `eventbridge-rule` 接，這個 module 不做。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

automation rule、custom action、insight、停用個別 control（之後用 `aws_securityhub_standards_control_association` 另加）、FSBP 與 CIS 以外的標準、central configuration（configuration policy）、新版 Security Hub（`*_v2`）、IAM。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `standards` | `list(string)` | `[ "fsbp", "cis" ]` | 否 | 要訂閱的標準短名，module 換成 region 對應的 ARN：`fsbp`（AWS Foundational Security Best Practices v1.0.0）、`cis`（CIS AWS Foundations Benchmark v5.0.0）。預設兩個都訂。 |
| `control_finding_generator` | `string` | `"SECURITY_CONTROL"` | 否 | `SECURITY_CONTROL`（預設，同一個 control 在多個標準只產生一筆 finding）或 `STANDARD_CONTROL`（每個標準各一筆）。Organizations 模式只有管理員帳號能改。 |
| `auto_enable_controls` | `bool` | `true` | 否 | 已訂閱的標準新增 control 時是否自動啟用（預設 `true`）。 |
| `finding_aggregator` | `object` | `null` | 否 | 跨 region 彙整 finding 到這個 region。`linking_mode`：`ALL_REGIONS`、`ALL_REGIONS_EXCEPT_SPECIFIED`、`SPECIFIED_REGIONS`、`NO_REGIONS`；`ALL_REGIONS_EXCEPT_SPECIFIED` 與 `SPECIFIED_REGIONS` 要給 `regions`（要排除或納入的 region），`ALL_REGIONS` 與 `NO_REGIONS` 不能給。`null`（預設）時不建 aggregator。 |
| `organization` | `object` | `null` | 否 | organization 設定（local configuration），只在 Security Hub 的委派管理帳號給。`auto_enable` 是新成員帳號是否自動啟用 Security Hub；`auto_enable_standards` 是 `DEFAULT`（新成員自動開 AWS 的預設標準：FSBP 與 CIS v1.2.0）或 `NONE`。`null`（預設）時不管理 organization 設定。 |
| `region` | `string` | `null` | 否 | Security Hub 所在的 region；`null`（預設）用 provider 的 region。標準 ARN 也用這個 region 組出。Security Hub 是 regional 服務，每個 region 各呼叫一次。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `account_id` | 啟用 Security Hub 的帳號 ID。 |
| `standards_subscription_arns` | 標準短名 → 訂閱的 ARN。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/securityhub
```
