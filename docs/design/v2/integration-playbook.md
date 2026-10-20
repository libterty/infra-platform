# 整合流程：把一個既有專案的 infra 改寫成本 repo 的範本

> 每整合一個專案（下稱來源專案）都照這份做。第一次套用是 example2，設計見 [`design-docs.md`](./design-docs.md)。
> 範本以既有專案為參考改寫；整份流程的前提是「來源專案的任何識別資訊都不能進 repo」。

## 1. 產出

每個來源專案產出：

- `templates/example<N>/infra/`：用 HCP private registry 引用 module 的範本。
- 補進 registry 的 module（新增或擴充），各自發版、到 HCP 登記。
- `docs/design/v<M>/` 底下的設計增補與實作流程，或在現有 v2 文件加一節。
- 本機的 `docs/design/v2/private/<代號>-mapping.md`：真名對照表與去機密掃描 pattern。這個目錄在 `.gitignore` 裡，**不進版控**。

來源專案在 repo 內一律用代號（project-a、project-b、project-c…），不寫真實名稱、客戶名稱或業務內容。

## 2. 限制

- 不連 AWS。Terraform 只跑 `init -backend=false`（從 HCP 抓 module），以及建在它上面的 `validate`、`test`（`mock_provider`）。不跑 `plan`、`apply`、帶 backend 的 `init`。
- 環境只有 `dev`、`sit`。來源專案的其他環境名稱不能出現在 code、tfvars、tests、註解、commit message。來源專案用環境名稱判斷的邏輯（例如「某環境不建 bastion」）改成明確的開關。
- 不從來源專案複製 tfvars、tfbackend 或任何值，全部重新寫成佔位值：
  - 帳號：`111111111111`（dev）、`222222222222`（sit）、`444444444444`（外部對端）
  - 網段：`10.10.0.0/16`；外部對端用 `10.250.0.0/16`；文件用網段 `198.51.100.0/24`、`203.0.113.0/24`
  - 網域：`example.com`；email：`ops@example.com`
  - state bucket：`<state-bucket>`
- 不改來源專案。
- module 先發布，範本才能對 registry 驗證，所以永遠是兩個 PR：先 module，後範本。

## 3. 步驟

### 3.1 盤點（唯讀）

1. 列出來源專案每個 stack 的 resource 與 data source 類型和數量（忽略 `.terraform*/`）。
2. 讀 apply 順序腳本、跨 stack 傳值的方式（SSM 路徑、tfvars 手抄、remote state）、tests、envs。
3. 用 `find` 讀被 `.gitignore` 擋住的 tfvars，找出所有識別資訊與機密值。
4. 對照本 repo 的靜態規則（v1 design §5.6 的 S1–S9），列出來源專案哪些寫法會被擋。

### 3.2 對照 module

每一種 resource 類型決定處理方式，填成一張表（範例見 design §2 與 §5.2）：

| 處理方式 | 什麼時候用 |
|---|---|
| 既有 module | 介面已經涵蓋 |
| 擴充既有 module（MINOR） | 少幾個變數；預設值必須維持原本行為，既有 tests 不改就要全過 |
| 新 module（`0.1.0`） | 沒有 module 管這類 resource |
| 拿掉 | 遷移期的寫法、重複的功能、可以用 module 內建功能取代的（例如 dashboard） |
| stack 內原生 resource | 盡量不用；要用就加進 S8 例外清單，並改 v1 design §5.3 的表 |

擴充既有 module 時注意版本：0.x 期間 `feat` 升 MINOR。既有範本寫的 `~> 0.1.0` 不會自動吃到 `0.2.0`。

### 3.3 拍板

用選擇題問使用者，至少涵蓋：

- 保留來源專案的 stack 拆法，還是改成 project-infra 的拆法。
- 來源專案已知的設計問題要照抄還是修正。
- 缺 module 的資源：補 module、stack 內原生 resource、或拿掉。
- 發版方式。

決策寫進設計文件的決策表，附理由。

### 3.4 實作

照 [`implement-process.md`](./implement-process.md) 的 Phase 結構：module（擴充 → 新增 → 共用設定 → 發版與 HCP 登記），然後範本（`validate.sh` 支援 → 骨架 → 前段 stack → 後段 stack → 收尾）。每個 Phase 先寫 tests，主 agent 自己重跑驗收才 commit，每個 Phase 結束先跟使用者確認。

### 3.5 發版與 HCP 登記

照 [`releasing-modules.md`](../../guides/releasing-modules.md) 與 [`hcp-registry-setup.md`](../../guides/hcp-registry-setup.md)。打 tag、push、建 Release、HCP 登記之前先問使用者。

## 4. 去機密

### 4.1 泛化規則

| 類別 | 改成 |
|---|---|
| 專案名、資源前綴 | `example`、`example-<env>` |
| 服務名 | 依角色取通用名，例如 `api`、`worker`、`agent` |
| 業務內容（guardrail 詞彙、文案、topic、商品或客戶相關的規則） | 中性的示意內容 |
| 註解 | ticket 編號、PR 編號、來源專案的 ADR 與文件路徑、客戶名稱、業務背景全部刪掉；只留程式碼看不出來的原因，改寫成英文 |
| AWS 公開識別（model id、managed rule group 名稱、`alias/aws/*`） | 可以保留 |

### 4.2 掃描

每個專案在 private 檔裡維護自己的 pattern，至少涵蓋：

1. 專案名、客戶名、產品名、業務用語
2. ticket 與內部文件引用
3. 原本的服務名
4. 12 位數帳號（排除佔位值）
5. 真實網段與 AWS 資源 id（`vpc-`、`sg-`、`subnet-`、`pcx-`）
6. 網域（排除 `example.com` 與公開服務網域）
7. ARN 裡的真實資源 id
8. dev、sit 以外的環境名稱（只掃新範本與新增或擴充的 module）
9. 非 `example.com` 的 email

另外從來源專案的 tfvars、tfbackend 抽出所有字串常值，在 scratchpad 反向比對整個 repo，用完刪掉；機密值不能寫進任何 pattern 檔。

什麼時候跑：每個 Phase 的 commit 前、PR 送出前、合併前。commit message、PR 標題與描述、branch 名稱另外人工看。
