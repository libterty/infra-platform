# infra-platform v5 設計文件：tflint aws ruleset 與 terraform-docs

> 狀態：設計草案，第一版。§3 是使用者拍板的決策（2026-10-23）。審過才進實作，步驟見 [`implement-process.md`](./implement-process.md)。
> 範圍：平台本身的兩件待辦：tflint 加上 `tflint-ruleset-aws`；42 個 module 的 README 輸入／輸出表改由 terraform-docs 產生，`description` 改寫成台灣繁體中文。範本的 stack 程式碼與行為不變。
> 文中路徑除非特別註明，都是 repo 內相對路徑。工具版本與實測數字是 2026-10-23 查證的結果，來源列在 §10。

## 1. 結論

- **tflint**：`.tflint.hcl` 加 `tflint-ruleset-aws` 0.49.0，套用在 `validate.sh` 會 lint 的所有目錄（module、examples、範本 stack）。範本 stack 另外用 `--call-module-type=all` 逐一帶入每份 tfvars 再跑一次，讓 tfvars 裡的規格值（instance type 這類）也被檢查到。不開 `deep_check`，整個流程不需要 AWS 憑證。實測 129 個目錄、114 次 tfvars 組合都是 0 個問題，不用關 rule，也不用改程式碼。
- **terraform-docs**：0.24.0，用自訂 template 產生中文表頭的輸入／輸出表，注入 README 裡 `<!-- BEGIN_TF_DOCS -->`／`<!-- END_TF_DOCS -->` 之間。`validate.sh` 新增靜態規則 S11，用 `--output-check` 擋住 README 跟程式碼不一致。
- **description 改中文**：42 個 module 的 392 個變數、182 個 output 的 `description` 改寫成台灣繁體中文，並把現在只寫在 README 表格裡的約束、預設行為、相依條件搬進 description。註解與 `error_message` 維持英文。
- **發版**：每個 module 一個 `fix(<module>)` commit，42 個 module 都發 PATCH，HCP registry 才會顯示新的表格。分 7 批，每批合併後一次合併一個 release PR。
- **不碰 AWS**：tflint 不開 `deep_check`、terraform-docs 只讀 `.tf`、`validate.sh` 只跑 `init -backend=false`。沒有任何一步會跑 `plan`、`apply`，也不會觸發 HCP 的 run。

## 2. 查證時發現、會影響設計的事

1. **aws ruleset 在現有程式碼上是 0 個問題**：module 42、examples 54、範本 stack 33 個目錄全部乾淨；故意寫錯 instance type 的 probe 會被抓到（包括值來自 tfvars 的情況），證明 plugin 確實在跑。
2. **`tflint --init` 要先跑**：沒裝 plugin 時 `tflint` 直接失敗。裝好之後可以離線執行。安裝時驗 GitHub attestation 與 checksum，每次約打 5 次 GitHub API；匿名額度是每個 IP 每小時 60 次，CI 要給 `GITHUB_TOKEN`。
3. **examples 才是 aws rule 對 module 的實際覆蓋範圍**：tflint 預設 `call_module_type=local`，examples 用 `source = "../.."` 呼叫 module，tflint 會用 example 給的值評估 module 裡的 resource。範本 stack 只呼叫 registry module，要用 `--call-module-type=all` 才會展開。
4. **terraform-docs 內建的 `{{ .Inputs }}` 只能產生英文**（`## Inputs`、`n/a`、`yes`／`no`），沒有選項可以改。要用 `.Module.Inputs` 自訂 template。
5. **README 少了 marker 時，inject 模式會把表格附加在檔尾**，不會報錯。所以導入 marker 與產生表格要在同一個 commit 完成。
6. **多行型別會弄壞 markdown 表格**，16 個變數的型別裡還夾著英文註解。template 要先拿掉註解、壓成一行，再依 §3 D2 收成外層型別。
7. **`sanitizeMarkdownTbl` 不跳脫角括號**：沒放進反引號的 `<name_prefix>` 在 GitHub 上會被當成 HTML 標籤吃掉。現在有 41 個 description 裸寫了 `<…>`。
8. **output 沒有型別**：41 個 module 的輸出表有手寫的「型別」欄，產生器做不出這一欄，改寫時把有用的型別資訊寫進 description（例如「key 同 `target_groups` 的 map」）。
9. **有 4 個 module 在「## 輸入」裡放了子表或點號列**（nlb、lb-traffic-breaker、eks-addons、bedrock-knowledge-base），產生器會把它們蓋掉，要先搬出去。
10. **有 6 個變數沒寫 description**（alb×3、ecs-service-alarms×2、nlb×1）；terraform ruleset 的 `terraform_documented_variables`／`terraform_documented_outputs` 只會抓到這 6 個。
11. **`docs:` commit 不會發版**：`release-please-config.json` 沒設 `changelog-sections`，只有 `feat`、`fix`、`perf`、`revert` 會開 release PR。`docs/guides/releasing-modules.md` 的 semver 表把 `docs:` 列在 PATCH，跟實際行為不符，要一起改。
12. **registry 顯示的是 tag 當下的內容**：只改 `main` 不會更新 HCP 上的 README 與 Inputs 分頁。中文 description 在 HCP 的顯示還沒實測。
13. **三份文件規定 description 只用英文**：`CONTRIBUTING.md`〈語言〉、`docs/guides/releasing-modules.md` 步驟 3，以及 v1 design 決策 26。v5 取代 v1 決策 26 的這一部分；前兩份要改寫。
14. **範本 stack 用 `~> 0.x.y` 約束 module 版本**（143 處 `~> 0.1.0`，其他是 `~> 0.2.0` 等），PATCH 版會被自動帶進範本。所以改寫 description 的 commit 不能有任何行為變更（§7）。
15. **`*.md` 在 `--changed-since` 裡算「不影響驗證」**：只改 README 的 PR 不會跑任何目錄的 init 到 tflint。S11 必須放在每次都全掃的靜態規則階段。
16. **vendor 進客戶 repo 的 module 也帶著 README**，但客戶 repo 沒有 `.terraform-docs.yml`，也不一定裝了 terraform-docs。

## 3. 決策

使用者拍板（2026-10-23）：

| # | 決策 | 選項 |
|---|---|---|
| D1 | 表格語言 | **description 改成台灣繁體中文**，再由 terraform-docs 產生中文表格 |
| D2 | 型別欄 | **收成外層型別**：`map(object({…}))` 顯示成 `map(object)`、`object({…})` 顯示成 `object`，跟現在手寫的表一樣；欄位、預設與限制寫在 description，太長的放到 marker 外的欄位小節 |
| D3 | tflint 範圍 | **module、examples 與範本 stack 都套**；範本 stack 另外帶入每份 tfvars、用 `--call-module-type=all` 跑 |
| D4 | 交付 | **一個 v5 里程碑**：設計文件審過才實作，一個 Phase 一層 stacked PR |
| D5 | 發版 | **42 個 module 都發 PATCH**：每個 module 用 `fix(<module>)` commit，CHANGELOG 會列在 Bug Fixes |

照 v1 到 v4 的慣例定下的判斷（審閱時可以推翻）：

| # | 判斷 | 理由 |
|---|---|---|
| K1 | tflint 維持 0.64.0，aws ruleset 釘 0.49.0 | tflint 0.65.0 是 2026-10-22 才發的，不到兩週 |
| K2 | plugin 放在 `.cache/tflint-plugins`（`TFLINT_PLUGIN_DIR`），CI 用 `actions/cache` 快取，key 用 `.tflint.hcl` 的 hash | 跟現有 `.cache/plugins` 一致；`validate.sh` 不寫使用者家目錄 |
| K3 | CI 直接下載 terraform-docs binary，比對寫死在 workflow 的 sha256；不用官方 Action | 官方 Action 綁的是舊的 0.20.0，而且是 docker image，釘了 SHA 也只釘到 `action.yml` |
| K4 | 一組 marker 包住「## 輸入」與「## 輸出」兩節 | 42 份 README 裡這兩節都相鄰 |
| K5 | 輸出表只有「名稱｜說明」兩欄 | output 沒有型別可以產生 |
| K6 | 列的順序照程式碼（`sort.enabled = false`） | 37/42 個 README 的列順序本來就跟程式碼一致，diff 最小 |
| K7 | S11 只在 repo 根目錄有 `.terraform-docs.yml` 時執行，只檢查 `modules/*` | vendor 到客戶 repo 時不會因為缺設定或缺工具而失敗 |
| K8 | terraform-docs 跟 tflint 一樣是必要工具，找不到就失敗 | 跳過的話 S11 等於沒有 |
| K9 | 最後一個 Phase 打開 `terraform_documented_variables`、`terraform_documented_outputs` | 6 個缺 description 的變數在改寫時補上，以後不會再出現空白描述 |
| K10 | 改寫分 7 批，依 README 的 module 分類；第一批挑小的 module | 第一批發版後先到 HCP 確認中文顯示正常，再做後面的批次 |

## 4. tflint

`.tflint.hcl` 加一個 block，其他不動：

```hcl
plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
```

`deep_check` 不寫，維持預設的 `false`，所以 tflint 不會呼叫任何 AWS API。

`validate.sh` 的改動：

- 設 `TFLINT_PLUGIN_DIR="${repo_root}/.cache/tflint-plugins"`；在 `command -v tflint` 檢查之後、逐目錄迴圈之前跑一次 `tflint --init --config=<repo>/.tflint.hcl`。
- 範本 stack（現在 Step 6a 用目錄結構判斷的那一類）在原本的 tflint 之後，對 `envs/*.tfvars` 與 `envs/examples/*.tfvars` 逐一跑 `tflint --call-module-type=all --var-file=<file>`。module 已經由前面的 `init` 下載到 `TF_DATA_DIR`，不用另外 init。
- module 與 examples 維持原本的 tflint 呼叫方式。

aws ruleset 只檢查它有規則的 resource：ElastiCache 的 node type、EC2 的 instance type、`aws_db_instance` 的 instance class 會被檢查；Aurora 的 `aws_rds_cluster_instance` 沒有對應規則，範本的 `db_instance_class` 檢查不到（E1 實測）。

CI（`.github/workflows/ci.yml`）：

- 加一個 `actions/cache`，快取 `.cache/tflint-plugins`，key 是 `tflint-${{ runner.os }}-${{ hashFiles('.tflint.hcl') }}`。
- Validate 那一步加 `GITHUB_TOKEN: ${{ github.token }}`，給 `tflint --init` 避開匿名額度。workflow 的 `permissions: contents: read` 已經夠用。

在客戶 repo 跑 `validate.sh`（vendor 情境）時，第一次也會下載 plugin；這點寫進 `docs/guides/delivering-to-customer.md`。

## 5. terraform-docs

### 5.1 設定

repo 根目錄新增 `.terraform-docs.yml`：

```yaml
formatter: "markdown table"
version: ">= 0.24.0, < 0.25.0"
sections:
  show: [inputs, outputs]
content: |-
  ## 輸入

  | 名稱 | 型別 | 預設 | 必填 | 說明 |
  |---|---|---|---|---|
  {{- range .Module.Inputs }}
  | `{{ .Name }}` | `<外層型別>` | {{ if .Required }}無{{ else }}`<一行的預設值>`{{ end }} | {{ if .Required }}是{{ else }}否{{ end }} | {{ .Description | tostring | sanitizeMarkdownTbl }} |
  {{- end }}

  ## 輸出

  | 名稱 | 說明 |
  |---|---|
  {{- range .Module.Outputs }}
  | `{{ .Name }}` | {{ .Description | tostring | sanitizeMarkdownTbl }} |
  {{- end }}
output:
  file: README.md
  mode: inject
  template: |-
    <!-- BEGIN_TF_DOCS -->
    {{ .Content }}
    <!-- END_TF_DOCS -->
sort:
  enabled: false
settings:
  anchor: false
  html: false
  escape: true
  lockfile: false
  read-comments: false
```

`<外層型別>` 的做法：先用 `regexReplaceAll` 拿掉 `#` 註解、把空白壓成一個，再把第一個 `({` 到最後一個 `})` 之間整段拿掉。例如 `map(object({ … }))` 會變成 `map(object)`，`list(object({ … }))` 會變成 `list(object)`，`string`、`map(string)` 維持原樣。實作時用 42 個 module 的實際型別驗證這個 regex（implement-process E2）。

`<一行的預設值>` 用 `.GetValue`，把空白壓成一個。現在非空的複合預設值只有 7 個，長度可以接受。

### 5.2 S11

`validate.sh` 的靜態規則加一條：

- **S11**：repo 根目錄有 `.terraform-docs.yml` 時，對每個 `modules/*/README.md` 有 `BEGIN_TF_DOCS` marker 的 module 跑 `terraform-docs -c .terraform-docs.yml --output-check modules/<m>`，不一致就失敗。訊息要提示怎麼重新產生。
- 過渡期（E3–E9）只檢查已經有 marker 的 module；E10 改成「每個 module 都必須有 marker」。
- 不受 `--changed-since` 影響，每次都全掃（§2 第 15 點），42 個 module 約 1 秒。

重新產生用同一份設定：`terraform-docs -c .terraform-docs.yml modules/<m>`。`CONTRIBUTING.md` 與 `docs/guides/releasing-modules.md` 寫這個指令。

CI 下載 `terraform-docs-v0.24.0-linux-amd64.tar.gz`，用 `sha256sum -c` 比對寫死的 `9005daf969de0b50134493a2c00078b49f5f5b39d021cda7c89bf4d4f3d776d3`，放進 `PATH`。

## 6. description 改寫規則

### 6.1 寫什麼

- 用台灣繁體中文，結論先講：這個值是什麼、用來做什麼。
- 單一變數的約束、範圍、預設行為、相依條件都寫進 description：例如「7–30 天」、「`null` 時不建立」、「`target_groups` 非空時必填」。這些現在只寫在 README 表格裡，產生器會蓋掉。
- 「必填：視情況」這類產生器表達不出來的語意，寫在 description 開頭。
- object 與 map(object)：列出欄位與各自的預設、限制。一個儲存格放不下時（nlb 的 `target_groups`、`listeners`，lb-traffic-breaker 的 `breakers`，eks-addons 的 `auto_mode`，agentcore-gateway 的 `targets` 這類），description 只寫一句話加「欄位見〈…〉」，欄位表放到 marker 外面的新小節。
- output：寫清楚值的形狀，例如「key 同 `target_groups` 的 map，值是 target group ARN」，取代原本的型別欄。
- 識別字、欄位名稱、列舉值、`<…>` 樣式的名稱一律放進反引號（§2 第 7 點）。
- 跨變數的行為、AWS 的坑、成本、未實測的事項，維持寫在 README 的「## 注意」，不塞進 description。
- 補上 6 個缺 description 的變數。

### 6.2 不改什麼

- 註解、`error_message` 維持英文。
- 不改任何型別、預設值、validation 條件、resource 或 output 的值。
- README 的「## 注意」「## 刻意不做」等其他節維持原樣，只動 marker 範圍內的表格；搬出來的子表、點號列放在 marker 外面。

### 6.3 規則文件

- `CONTRIBUTING.md`〈語言〉改成：「`description` 用台灣繁體中文，識別字放進反引號；註解與 `error_message` 只用英文。」拿掉「不中英混雜」，因為中文 description 一定會夾英文識別字。
- `docs/guides/releasing-modules.md`：步驟 3 同上；步驟 4 改成「介面有變就重新產生 README 表格：`terraform-docs -c .terraform-docs.yml modules/<m>`」；semver 表把 `docs:` 從 PATCH 那一列移到新的一列「不發版」。
- `README.md`〈開發〉與 `CONTRIBUTING.md`〈開發環境〉的工具清單加上 terraform-docs 0.24.0，S1 到 S10 改成 S1 到 S11。
- v1 design 決策 26 不改歷史文件，由這份文件取代。

## 7. 發版

- 每個 module 一個 commit：`fix(<module>): rewrite the input and output descriptions in Chinese`，內文說明這是文件變更、行為不變。release-please 會替每個 module 開一個 PATCH release PR。
- PR 標題不用 Conventional Commit 格式，用 merge commit 合併（`releasing-modules.md`〈一個 PR 動到多個 module〉）。
- 一批合併後會同時有好幾個 release PR，照 `releasing-modules.md`〈同時有多個 release PR〉一次合併一個，等 Release run 跑完、`gh release view` 查得到再做下一個。
- 每發一版就確認 HCP 讀到新版本（`version-statuses`）。第一批第一個 module 發版後，另外到 HCP 看 Inputs 分頁與 README 的中文顯示正常，才繼續。
- 範本 stack 的 `~>` 約束會自動帶入新的 PATCH 版；CI 的「Registry versions」摘要可以看到範本解析到的版本。因為行為不變，範本不用改。

**行為不變的證明**（每個 module 都要過）：

1. `terraform-docs json` 前後比對，拿掉 `description` 之後完全相同（名稱、型別、預設、必填）。
2. `.tf` 的 diff 只落在 `description` 的值上（腳本逐行檢查）。
3. `scripts/validate.sh modules/<m>` 通過（測試、examples、tflint、S11）。

## 8. Phase

見 [`implement-process.md`](./implement-process.md)。摘要：

| Phase | 內容 |
|---|---|
| E0 | 這份設計與實作流程 |
| E1 | tflint aws ruleset：`.tflint.hcl`、`validate.sh`、CI、文件 |
| E2 | terraform-docs：`.terraform-docs.yml`、S11、CI、規則文件 |
| E3–E9 | 7 批 description 改寫與 README 產生，每批合併後發版 |
| E10 | S11 改成每個 module 都要有 marker、打開 documented 規則、收尾文件 |

## 9. 風險

| 風險 | 影響 | 處理 |
|---|---|---|
| 改寫時不小心改到型別、預設或 validation | PATCH 版自動進到範本，行為改變 | §7 的三項證明；diff 不只 description 就擋 |
| 中文 description 在 HCP 顯示異常 | registry 上的表格壞掉 | 第一個發版後先人工看過，有問題就停下來，後面的批次先不發 |
| 42 個 release PR 互相衝突 | 發版拖很久 | 分 7 批，每批一次一個，照既有流程重建 |
| GitHub 的 tag webhook 漏掉 | HCP 少一個版本 | release-please 一次只建一個 tag；每發一版就確認 HCP 的版本清單，漏了照 `hcp-registry-setup.md` 重新登記 |
| `tflint --init` 被 GitHub 匿名額度擋 | CI 失敗 | CI 給 `GITHUB_TOKEN`，plugin 有快取 |
| aws ruleset 升版後冒出新問題 | CI 突然失敗 | 版本釘死在 `.tflint.hcl`，升版是明確的 PR |
| 客戶 repo 跑 `validate.sh` 時缺 plugin 或 terraform-docs | vendor 流程失敗 | K7：S11 只在有 `.terraform-docs.yml` 時跑；`tflint --init` 寫進交付文件 |

## 10. 來源

- tflint-ruleset-aws releases（v0.49.0，2026-09-19）與 README〈Requirements〉：https://github.com/terraform-linters/tflint-ruleset-aws/releases
- tflint〈Avoiding rate limiting〉與 plugin 驗證：https://github.com/terraform-linters/tflint/blob/master/docs/user-guide/plugins.md
- terraform-docs v0.24.0（2026-05-10）與 sha256：https://github.com/terraform-docs/terraform-docs/releases/tag/v0.24.0
- terraform-docs 設定與 inject 模式：https://terraform-docs.io/user-guide/configuration/
- release-please 預設 changelog sections：https://github.com/googleapis/release-please/blob/main/docs/customizing.md
- 實測紀錄：129 個目錄的 tflint JSON、42 個 module 的中文表頭產出、description 與 README 的逐列比對（2026-10-23，在本機 scratchpad 進行，未進 repo）。
