# 四個團隊的責任與交接點

結論：platform team 擁有 module、CI 與發版；專案 app team 擁有自己 repo 的 `infra/`，只引用 module、不改 module；FDE 負責把專案交付到客戶環境，客戶環境的差異回報給 platform team 決定；core app team 目前在這個 repo 沒有東西。邊界寫在 `.github/CODEOWNERS`，要搭配分支保護的「Require review from Code Owners」才有效。四個團隊還沒正式成立，team slug 目前是佔位符。

## 責任

| 團隊 | 擁有 | 負責 | 不負責 |
|---|---|---|---|
| platform team | `modules/`、`.github/`、`scripts/`、`docs/adr/`、release-please 的兩個設定檔 | module 介面與 semver、CI、發版（含第一次手動打 tag）、安全基線、審查範本變更 | 各專案的 tfvars 與 apply |
| core app team | 這個 repo 暫無 | AP 層共用元件（SDK、服務範本）之後比照本 repo 的發版模式另開 repo；需要 infra 支援時對 platform team 開 issue | infra module |
| 專案 app team | 自己 repo 裡的 `infra/` | 複製範本、釘版本、升版、自己的 tfvars 與 apply、回報 module 的 bug 或需求 | module 內部實作 |
| 專案 FDE team | 自己的交付 repo | vendoring、provider 鏡像、跟客戶約定 SSM 合約、回報客戶環境差異 | 決定差異要不要收進 module |

各團隊的操作指南：

| 團隊 | 先讀 |
|---|---|
| platform team | [`releasing-modules.md`](./releasing-modules.md) |
| 專案 app team | [`project-infra-standard.md`](./project-infra-standard.md)、[`consuming-modules.md`](./consuming-modules.md)、[`observability.md`](./observability.md)、[`llm-agentcore.md`](./llm-agentcore.md) |
| 專案 FDE team | [`delivering-to-customer.md`](./delivering-to-customer.md) |

## 交接點

| 交接 | 從 → 到 | 形式 |
|---|---|---|
| module 新需求或 bug | 專案 app team、FDE → platform team | 本 repo 的 GitHub issue，附消費端的呼叫方式與期望行為 |
| 新版發布 | platform team → 所有消費端 | release-please 產生的 tag 與 CHANGELOG；MAJOR 版（以及 0.x 的破壞性變更）另外通知 |
| 範本改版 | platform team ↔ 專案代表 | PR，雙方都要核准（CODEOWNERS 對 `/templates/` 設了兩方） |
| 客戶環境差異 | FDE → platform team | issue，platform team 決定收進 module（通常是 MINOR）或留在專案；欄位見 `delivering-to-customer.md`〈客戶環境差異怎麼回報〉 |
| 交付給客戶 | FDE → 客戶 | vendored module、`vendor/modules/VERSIONS`、SSM 合約表（`infra/README.md`）、`delivering-to-customer.md` |

## 對到 CODEOWNERS

`.github/CODEOWNERS` 的規則（GitHub 對同一路徑取最後一條符合的規則，所以具體路徑寫在後面）：

| 路徑 | 審查者 | 對應的責任 |
|---|---|---|
| `*`（預設） | platform team | 沒有特別指定的都歸 platform team |
| `/modules/`、`/.github/`、`/scripts/`、`/docs/adr/`、`/release-please-config.json`、`/.release-please-manifest.json` | platform team | module、CI、發版 |
| `/templates/`、`/docs/guides/project-infra-standard.md`、`/docs/guides/consuming-modules.md` | platform team ＋ 專案代表 | 範本與消費端規範，兩方都要核准 |
| `/scripts/vendor-modules.sh`、`/docs/guides/delivering-to-customer.md` | platform team ＋ FDE | 交付流程 |
| `/docs/guides/team-roles.md` | 四個團隊 | 這份分工本身 |

`releasing-modules.md`、`observability.md`、`llm-agentcore.md` 沒有特別指定，歸預設的 platform team。

team slug 現在是 `@<org>/platform-team`、`@<org>/core-app-team`、`@<org>/project-app-reps`、`@<org>/fde-team`，團隊成立後填入實際值，路徑規則不用改。新增 module 或 stack 也不用改這份檔：module 都在 `/modules/` 底下，stack 都在 `/templates/` 底下。
