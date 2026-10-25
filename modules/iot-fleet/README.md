# iot-fleet

一個裝置群在 IoT Core 的設定：thing type、thing group 階層、IoT policy、role alias、fleet provisioning（by claim）template，以及選填的 CA 註冊（`SNI_ONLY`）。不建 thing 與裝置憑證，裝置靠 fleet provisioning 自己開通。

## 用法

```hcl
module "iot_fleet" {
  source = "git::https://github.com/<org>/<repo>.git//modules/iot-fleet?ref=iot-fleet-v0.1.0"

  thing_groups = {
    alpha-dev            = {}
    alpha-dev-unverified = { parent = "alpha-dev" }
    alpha-dev-fleet      = { parent = "alpha-dev" }
  }

  policies = {
    alpha-dev-device = {
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = "iot:Connect"
        Resource = "arn:aws:iot:ap-northeast-1:111111111111:client/$${iot:Connection.Thing.ThingName}"
      }]
    }
  }

  role_alias = {
    alias    = "alpha-dev-tes"
    role_arn = module.tes_role.role_arn
  }

  provisioning_template = {
    name                  = "alpha-dev-fleet"
    provisioning_role_arn = module.provisioning_role.role_arn
    enabled               = true
    template_body         = jsondecode(file("${path.module}/provisioning-template.json"))
  }
}
```

完整範例（含 provisioning template 的內容）見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 建立條件 | map 是空的、物件是 `null` 就不建 |
| thing group 階層 | `parent` 指同一個 map 裡的群組，最多 4 層，逐層建立（上層先建） |
| IoT policy | 文件以物件傳入，module `jsonencode`；`Allow` 的 `iot:*` 或 `*` 不能搭 `Resource` `*` |
| role alias | `credential_duration` 預設 3600 秒，範圍 900–43200 |
| provisioning template | `type = "FLEET_PROVISIONING"`；hook 選填 |
| CA 憑證 | `certificate_mode = "SNI_ONLY"`，不送 verification certificate |
| tag | 給定的 `tags` 加上 `Name`（CA 憑證沒有名稱，不加） |

## 注意

- **不掛 pre-provisioning hook 的取捨**：`pre_provisioning_hook = null` 時，任何拿到 claim 憑證的人都能開通任意數量的裝置，拿到正式的裝置憑證與裝置 policy 的權限。不掛 hook 時至少要有這些補償控制：claim 憑證在 Terraform 外用 CSR 建立（私鑰不經過 Terraform）；claim policy 只能碰 `$aws/certificates/create/*` 與 `$aws/provisioning-templates/<name>/provision/*`；template 要求 `SerialNumber` 參數、thing 名稱用序號組出（同序號第二次開通會失敗）；開通的裝置先進 `unverified` 群組，確認後才搬進收部署的群組；每批生產結束就把 claim 憑證設成 `INACTIVE`；開啟 Device Defender audit 與 IoT logging。能建 Lambda 時，改掛 hook 查序號白名單（hook 回 `"allowProvisioning": true` 才繼續）。
- 裝置 policy 用 `${iot:Connection.Thing.ThingName}` 把 client id 與 topic 限縮到自己；在 HCL 字串裡要寫成 `$${iot:Connection.Thing.ThingName}`。Greengrass core device 不支援 thing policy variable，改用命名規則（例如 `client/<prefix>-core-*`）。
- policy 的檢查只擋 `iot:*`、`*` 搭 `Resource` `*`；其他過寬的寫法（例如 `iot:Publish` 搭 `topic/*`）要在 PR 審查時看。改 policy 會建新版本並設為預設，IoT policy 最多 5 個版本，provider 會刪掉最舊的非預設版本。
- thing group 的 `parent` 改了會 replace 群組，群組裡的 thing 會被移出；Greengrass 部署目標是群組時，裝置會解除安裝該部署的元件。
- `role_alias.role_arn`、`provisioning_role_arn`、`registration_template.role_arn` 都由呼叫端建立，這個 module 不建 IAM。provisioning role 用 `AWSIoTThingsRegistration` 的權限。
- CA 只收 `SNI_ONLY`：`DEFAULT` 模式要 verification certificate（證明持有私鑰），同 region 也只能一個帳號註冊同一張 CA。`SNI_ONLY` 的裝置連線時要送 SNI。
- 部署者要有 IoT 的 `CreateThingType`、`CreateThingGroup`、`CreatePolicy`、`CreatePolicyVersion`、`CreateRoleAlias`、`CreateProvisioningTemplate`、`RegisterCACertificate` 等動作，以及對上述 role 的 `iam:PassRole`。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

- 建 thing 與裝置憑證：`aws_iot_certificate` 不給 CSR 時私鑰會進 state；裝置由 fleet provisioning 開通。
- custom authorizer、domain configuration、billing group、dynamic thing group。
- `DEFAULT` 模式的 CA 註冊。
- policy 與 principal 的 attachment：憑證由 provisioning template 建立並掛 policy。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `thing_types` | `map(object)` | `{}` | 否 | thing type，名稱（1–128 字元，限英數字、`:`、`_`、`-`）→ 設定。`searchable_attributes` 最多 3 個。 |
| `thing_groups` | `map(object)` | `{}` | 否 | thing group，名稱（1–128 字元，限英數字、`:`、`_`、`-`）→ 設定。`parent` 是同一個 map 裡另一個群組的名稱，`null` 就是最上層；階層最多 4 層、不能成環。 |
| `policies` | `any` | `{}` | 否 | IoT policy，名稱（1–128 字元，限英數字與 `_+=,.@-`）→ policy 文件物件（`Version`、`Statement`），module 用 `jsonencode` 轉成 JSON。每個 statement 都要有 `Effect`、`Action`、`Resource`；不准 `Allow` 的 `Action` 含 `iot:*` 或 `*` 又搭 `Resource` `*`。裝置 policy 建議用 `${iot:Connection.Thing.ThingName}` 限縮到自己的 client id 與 topic。 |
| `role_alias` | `object` | `null` | 否 | IoT role alias（例如 Greengrass token exchange service 用的）；`null` 就不建。`role_arn` 由呼叫端建立，trust 要是 `credentials.iot.amazonaws.com`；`credential_duration` 單位秒，900–43200（預設 3600）。 |
| `provisioning_template` | `object` | `null` | 否 | fleet provisioning（by claim）的 template；`null` 就不建。`name` 1–36 字元，限英數字、`_`、`-`；`template_body` 是 template 物件（`Parameters`、`Resources`），module 用 `jsonencode` 轉成 JSON；`provisioning_role_arn` 由呼叫端建立，trust 要是 `iot.amazonaws.com`；`enabled` 必填。`pre_provisioning_hook.target_arn` 是 Lambda ARN，`null` 就不掛 hook（取捨見 README〈注意〉）。 |
| `ca_certificate` | `object` | `null` | 否 | 要註冊到 IoT Core 的 CA 憑證（例如 `acm-pca` 簽的）；`null` 就不註冊。`pem` 是 PEM 格式的 CA 憑證（不含私鑰）；`mode` 只能 `SNI_ONLY`（`DEFAULT` 要 verification certificate，module 不收）；`active` 預設 `true`；`allow_auto_registration` 預設 `false`；`registration_template` 是 JITP 用的 template 物件與 role。 |
| `tags` | `map(string)` | `{}` | 否 | 資源的 tag；`Name` 由 module 加上（CA 憑證沒有名稱，不加）。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `thing_type_arns` | thing type 名稱 → ARN。 |
| `thing_group_arns` | thing group 名稱 → ARN（所有層級）。 |
| `policy_names` | `policies` 的 key → IoT policy 名稱。 |
| `role_alias_arn` | role alias 的 ARN；沒建時是 `null`。 |
| `provisioning_template_name` | fleet provisioning template 名稱；沒建時是 `null`。 |
| `ca_certificate_id` | 註冊的 CA 憑證 ID；沒註冊時是 `null`。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/iot-fleet
```
