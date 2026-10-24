# 參與貢獻

這個 repo 放共用的 Terraform module 與專案 infra 範本。module、CI 與發版由 platform team 負責，各團隊的分工見 [`team-roles.md`](./docs/guides/team-roles.md)。發現 bug 或有需求請開 issue，要改程式碼請開 PR。參與之前請先讀[行為準則](./CODE_OF_CONDUCT.md)。

安全問題不要開 issue，照 [`SECURITY.md`](./SECURITY.md) 私下回報。

## 開 issue

issue 只能用表單開：

- bug 回報：module 行為不對、validation 擋錯或漏擋、文件跟程式碼對不上。
- module 需求：新增 module，或擴充既有 module。

兩種都請附消費端的呼叫方式與期望行為。貼上來之前先拿掉 secret、帳號 ID 與 state 內容。

## 開發環境

需要 terraform 1.15.8、tflint 0.64.0、terraform-docs 0.24.x（`brew install terraform-docs`）、bash 與 jq，不需要 AWS 憑證。tflint 的 aws ruleset 是 plugin，第一次跑 `scripts/validate.sh` 時會從 GitHub 下載到 `.cache/tflint-plugins`；遇到 GitHub API 額度限制時設定 `GITHUB_TOKEN`。範本的 stack 從 `app.terraform.io/libterty` 抓 module，要驗證範本就要先用該 organization 成員的帳號 `terraform login`。

```bash
scripts/validate.sh                      # 全部
scripts/validate.sh modules/<module>     # 只跑指定目錄
scripts/validate.sh --changed-since origin/main  # 只跑這次改動影響得到的目錄
```

`scripts/validate.sh` 依序跑：

1. `terraform fmt -check`。
2. 靜態規則 S1 到 S11。S11 用 terraform-docs 檢查 module README 的輸入／輸出表跟程式碼一致。
3. `terraform init -backend=false`、`validate`。
4. `test`：`required_providers` 裡的每個 provider 都要有 `mock_provider`。
5. `tflint`：內建的 terraform ruleset 加上 aws ruleset。`.tflint.hcl` 釘版本，不開 `deep_check`，不需要 AWS 憑證；第一次跑時 `tflint --init` 會下載 plugin，之後不連網。範本的 stack 另外用 `--call-module-type=all` 逐一帶入 `envs/` 底下的每份 tfvars 再跑一次，tfvars 裡的規格值（例如 ElastiCache 的 node type）也會被檢查。aws ruleset 沒有對應規則的 resource（例如 Aurora 的 `aws_rds_cluster_instance`）檢查不到。

腳本一開頭就清掉所有 `AWS_*`、`KUBE*`、`HELM*` 環境變數，並把 AWS 設定檔與 `KUBECONFIG` 指到 `/dev/null`，所以漏寫 mock 的測試會失敗，不會拿到本機的 session 或叢集。module 裡有本地 Helm chart（`charts/`）或 Lambda 程式碼的測試（`lambda/test_*.py`）時，裝了 `helm`、`python3` 也會一起檢查。

加 `--changed-since <rev>` 時，fmt 與靜態規則仍然掃全部，`init` 到 `tflint` 只跑受影響的目錄：

- 改到的目錄。
- 用本地路徑（`./`、`../`）引用它的目錄，例如 module 的 examples。
- 改到範本 stack 之外的檔案時，該範本的全部 stack。

範本從 registry 抓 module，所以只改 module 不會重跑範本。`docs/`、`*.md` 不算改動；`scripts/`、`.tflint.hcl`、`.github/` 這類其他檔案一改就跑全部。

CI（`.github/workflows/ci.yml`）跑同一支腳本：PR 用 `--changed-since`，只驗證這個 PR 影響得到的目錄；push 到 main、每週排程與手動觸發跑全部。fork 來的 PR 拿不到 registry 的 token，範本的 stack 會在 CI 的 init 失敗。

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

- 變數與 output 的 `description` 用台灣繁體中文，識別字放進反引號；README 的輸入／輸出表由 terraform-docs 從 description 產生。
- `.tf` 與 `.tftest.hcl` 裡的註解與 `error_message` 只用英文，不放 icon。註解只寫程式碼看不出來的原因。
- `README.md`、`CHANGELOG.md` 與 `docs/` 底下的文件用台灣繁體中文。

## 授權

送進這個 repo 的貢獻都以 [Apache-2.0](./LICENSE) 授權。
