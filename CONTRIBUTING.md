# 參與貢獻

這個 repo 放共用的 Terraform module 與專案 infra 範本。module、CI 與發版由 platform team 負責，各團隊的分工見 [`team-roles.md`](./docs/guides/team-roles.md)。發現 bug 或有需求請開 issue，要改程式碼請開 PR。參與之前請先讀[行為準則](./CODE_OF_CONDUCT.md)。

安全問題不要開 issue，照 [`SECURITY.md`](./SECURITY.md) 私下回報。

## 開 issue

issue 只能用表單開：

- bug 回報：module 行為不對、validation 擋錯或漏擋、文件跟程式碼對不上。
- module 需求：新增 module，或擴充既有 module。

兩種都請附消費端的呼叫方式與期望行為。貼上來之前先拿掉 secret、帳號 ID 與 state 內容。

## 開發環境

需要 terraform 1.15.8、tflint 0.64.0、bash 與 jq，不需要 AWS 憑證。範本的 stack 從 `app.terraform.io/libterty` 抓 module，要驗證範本就要先用該 organization 成員的帳號 `terraform login`。

```bash
scripts/validate.sh                      # 全部
scripts/validate.sh modules/<module>     # 只跑指定目錄
```

這支腳本做哪些檢查，見 [README〈開發〉](./README.md#開發)。CI 在 PR 上跑同一支腳本。fork 來的 PR 拿不到 registry 的 token，範本的 stack 會在 CI 的 init 失敗。

## 不能做的事

- 不跑 `terraform plan`、`apply`、帶 backend 的 `init`，也不跑任何 `aws` 指令。Terraform 只透過 `scripts/validate.sh` 跑 `init -backend=false`、`validate`、`test`。
- 不提交 secret、token、真實帳號 ID、state 或 plan 檔。範例裡的帳號、網段、網域都用佔位值，寫法見 [`integration-playbook.md`〈2. 限制〉](./docs/design/v2/integration-playbook.md#2-限制)。
- 新範本與新增或擴充的 module 裡，環境名稱只用 `dev`、`sit`。依環境改變行為的邏輯要改成明確的開關，不要判斷環境名稱。

## 改 module

完整流程與 semver 判斷見 [`releasing-modules.md`](./docs/guides/releasing-modules.md)，重點如下：

1. 一個 commit 只動一個 module 目錄。release-please 靠路徑判斷變更要記進哪個 module 的 CHANGELOG，一個 commit 動到兩個 module 就會寫進兩邊。
2. 先寫 `tests/` 再改實作。每條 validation 正反兩個方向各一個 run，`required_providers` 裡的每個 provider 都要有 `mock_provider`（只用 aws 的 module 就是 `mock_provider "aws"`，`validate.sh` 的 S1 會檢查）。
3. 擴充既有 module 時，新變數的預設值要維持原本的行為，既有 tests 不改也要全部通過。
4. 介面有變，就同步改該 module 的 `README.md` 輸入輸出表與 `examples/`。
5. 不要手改 `CHANGELOG.md` 的版本段落。合併到 `main` 後 release-please 會開 release PR，合併 release PR 才打 tag 並更新 CHANGELOG。
6. PR 描述寫清楚消費端換版後 `terraform plan` 會看到什麼，這決定版本是 MAJOR、MINOR 還是 PATCH。

新增 module 時，`release-please-config.json` 的 `packages` 與 `.release-please-manifest.json` 各加一行，`README.md` 的 module 表也要加。

`modules/` 底下不放 `provider`、`backend`、`.terraform.lock.hcl`；module 之間不互相呼叫；不用 `enable_xxx` 開關。

範本引用的是 HCP registry 上已發布的版本。module 與範本要一起改時開兩個 PR：先合併 module 的 PR，等 release-please 發版、HCP 讀到新版，再開範本的 PR。

## commit 與 PR

commit 用 Conventional Commits：`<type>(<scope>): <subject>`，scope 寫 module 名稱，或改的不是 module 時寫 `repo`。commit message 用英文。

```
feat(ecs-service): add sidecars for extra containers
fix(iam-role): reject allow statements with NotResource
```

開 PR 時照範本填檢查清單。審查者依 [`.github/CODEOWNERS`](./.github/CODEOWNERS) 指派。

## 語言

- `.tf` 與 `.tftest.hcl` 裡的註解、`description`、`error_message` 只用英文，不中英混雜，不放 icon。註解只寫程式碼看不出來的原因。
- `README.md`、`CHANGELOG.md` 與 `docs/` 底下的文件用台灣繁體中文。

## 授權

送進這個 repo 的貢獻都以 [Apache-2.0](./LICENSE) 授權。
