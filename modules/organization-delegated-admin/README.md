# organization-delegated-admin

在 AWS Organizations 的管理帳號開 trusted access，並把 GuardDuty、Security Hub、Inspector、Config、IAM Access Analyzer、CloudTrail 的管理委派給一個成員帳號（通常是資安帳號）。只在管理帳號 apply。

## 用法

```hcl
module "delegated_admin" {
  source = "git::https://github.com/<org>/<repo>.git//modules/organization-delegated-admin?ref=organization-delegated-admin-v0.1.0"

  delegated_admin_account_id = "333333333333"
  services                   = ["guardduty", "securityhub", "inspector", "config", "access-analyzer"]
  regions                    = ["ap-northeast-1", "us-east-1"]
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 每個服務的做法

每個服務用 AWS 文件規定的方式委派，不會對同一個服務重複註冊：

| 服務 | trusted access 的 service principal | 委派方式 | 範圍 |
|---|---|---|---|
| `guardduty` | `guardduty.amazonaws.com`、`malware-protection.guardduty.amazonaws.com` | `aws_guardduty_organization_admin_account`（GuardDuty `EnableOrganizationAdminAccount`） | 每個 region |
| `securityhub` | `securityhub.amazonaws.com` | `aws_securityhub_organization_admin_account`（Security Hub `EnableOrganizationAdminAccount`） | 每個 region |
| `inspector` | `inspector2.amazonaws.com` | `aws_inspector2_delegated_admin_account`（Inspector `EnableDelegatedAdminAccount`） | 每個 region |
| `config` | `config.amazonaws.com`、`config-multiaccountsetup.amazonaws.com` | `aws_organizations_delegated_administrator`，兩個 principal 各一筆 | organization 全域 |
| `access-analyzer` | `access-analyzer.amazonaws.com` | `aws_organizations_delegated_administrator` | organization 全域 |
| `cloudtrail` | `cloudtrail.amazonaws.com` | `aws_cloudtrail_organization_delegated_admin_account`（CloudTrail `RegisterOrganizationDelegatedAdmin`） | organization 全域 |

- GuardDuty、Security Hub、Inspector 的 API 會自己在 Organizations 註冊委派管理員；再寫一筆 `aws_organizations_delegated_administrator` 會撞到已經註冊的帳號，所以這三個不寫。Security Hub 的文件也說明用 Organizations API 指定的委派管理員不會反映到 Security Hub。
- CloudTrail 用自己的 API，因為它會順便在管理帳號建需要的 service-linked role。
- 所有委派都排在 trusted access 之後；destroy 時順序相反。

## 注意

- **只在管理帳號 apply**，執行身分要有 Organizations 與各服務的管理權限。organization 要開 all features。
- `delegated_admin_account_id` 不能是管理帳號：CloudTrail 會直接拒絕，其他服務的 AWS 建議也是分開。
- GuardDuty 規定所有 region 的委派管理員要是同一個帳號；Security Hub 也建議一樣。要多個 region 時，把 region 都放進 `regions`，不要對同一個 organization 呼叫這個 module 兩次：trusted access 與 Config、Access Analyzer、CloudTrail 的委派是全域的，第二次呼叫會重複註冊而失敗。
- 委派完之後，GuardDuty、Security Hub、Inspector 的 organization 自動啟用設定、Access Analyzer 的 ORGANIZATION analyzer、Config 的 organization aggregator 都在資安帳號用各自的 module 設定，不在這裡。
- 如果 organization 已經用 `aws_organizations_organization` 的 `aws_service_access_principals` 管 trusted access，同一個 principal 不要兩邊都管，否則會互相覆寫。
- 拿掉服務或 destroy 時，會用 Organizations API 關掉 trusted access。AWS 建議先由資安帳號停用該服務的 organization 設定、清掉資源，再關 trusted access；CloudTrail 關掉 trusted access 會刪掉成員帳號的 organization trail。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

- AWS Backup：委派管理員要管 backup policy 時，還需要管理帳號的 resource-based delegation policy（`aws_organizations_resource_policy`）、organization 開 backup policy 類型、cross-account monitoring 的設定，責任超出這個 module。
- 建 organization、OU、SCP、帳號。
- 委派其他服務（Macie、Detective、Firewall Manager 等）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `delegated_admin_account_id` | `string` | 無 | 是 | 被委派的帳號 ID（12 位數字），通常是資安帳號。必須是 organization 的成員帳號，不能是管理帳號。 |
| `services` | `set(string)` | 無 | 是 | 要委派的服務，至少一個：`guardduty`、`securityhub`、`inspector`、`config`、`access-analyzer`、`cloudtrail`。每個服務會開 trusted access，再用該服務規定的方式委派（見 README）。 |
| `regions` | `set(string)` | `[]` | 否 | GuardDuty、Security Hub、Inspector 要委派的 region，例如 `["ap-northeast-1", "us-east-1"]`；`[]`（預設）只委派 provider 的 region。這三個服務的委派是 regional，trusted access 與其他服務的委派是 organization 全域，只建一次。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `delegated_admin_account_id` | 被委派的帳號 ID。 |
| `trusted_service_principals` | 開了 trusted access 的 service principal 清單（已排序）。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/organization-delegated-admin
```
