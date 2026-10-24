# infra-platform v6 設計文件：project-infra 的 SSM 合約檢查

> 狀態：設計草案，第一版。§3 是使用者拍板的決策（2026-10-24）。審過才進實作，步驟見 [`implement-process.md`](./implement-process.md)。
> 範圍：替 `templates/project-infra` 加上跟 example2、example3 一樣的 SSM 合約靜態檢查，並補上 `stacks.sh`。stack 的程式碼與行為不變；example2、example3 不動。
> 文中路徑除非特別註明，都是 repo 內相對路徑。project-infra 的路徑都在 `templates/project-infra/infra/terraform/` 底下，下文省略這段前綴。

## 1. 結論

- 新增 `check-ssm-contract.sh`（放在範本目錄，跟 example2 一樣），`scripts/validate.sh` 看到就會自動執行。兩項檢查：
  1. 每個 stack 讀的 `"<stack>/<key>"`，都要由 apply 順序更早的 stack 發布，而且種類一致（`String` 或 `StringList`）。
  2. 同一個 env 的各 stack tfvars 裡，共用的值（`project`、`env`、`aws_region`、`expected_account_id`）必須一致，`env` 要等於檔名。
- **依 tfvars 算出來的 key 用樣式比對**：`${...}` 當成萬用字元。讀的樣式要被更早 stack 發布的樣式或寫死的 key 涵蓋，例如讀 `iam-base/role_agent_${k}_execution_arn` 由 `iam-base` 發布的 `role_${k}_arn` 涵蓋。
- 新增 `stacks.sh`：照 example2 的寫法，依 ORDER 對單一或全部 stack 跑 `init`／`validate`／`plan`／`apply`／`destroy`／`output`，拿掉 example2 的 bridge 與外部共用 env。ORDER 是 apply 順序的唯一來源，檢查腳本直接讀它。
- README 的〈apply 順序〉改成指向 `stacks.sh`，並說明這支檢查。
- 不碰 AWS：兩支腳本都只讀 HCL 與 tfvars；`stacks.sh` 只在使用者自己執行時才跑 terraform，驗證時一律 `--dry-run`。

## 2. 查證時發現、會影響設計的事

1. **example2 的檢查只看得懂寫死的 key**：它解析 `ssm-outputs.tf` 的 `published_strings`／`published_lists` 第一層 key，以及 `ssm-inputs.tf` 的 `ssm_input_*`／`shared_input_*` map。
2. **project-infra 約一半的發布是算出來的**：`network`（`sg_${k}_id` 等 4 種）、`iam-base`（`role_${k}_arn` 等 3 種）、`containerimage`（`ecr_${k}_url` 等 6 種）、`agent`（`agent_runtime_${k}`）、`iam-app`（`role_${k}_task_arn`、`ecs_exec_${k}`）都是 `merge({ for ... : "prefix_${k}_suffix" => ... })`。
3. **讀取也有算出來的，而且不只在 `ssm-inputs.tf`**：`application/agent.tf`、`application/tracing.tf` 另外呼叫 `ssm-read`，key 寫成 `"agent/agent_runtime_${replace(r, "-", "_")}"` 這類含引號的運算式。
4. **`iam-app/agent-policies.tf` 有 `"runtime/${r}"`、`"service/${s}"`** 這類不是 SSM key 的字串；第一段不是 stack 名稱，所以只要限定「第一段是 ORDER 裡的 stack」就不會誤判。
5. **project-infra 沒有 `stacks.sh`**：順序只在 README〈apply 順序〉的表格。
6. **9 個 stack 都有 `project`、`env`、`aws_region`、`expected_account_id`**（`common.tf`，S5 已確保各 stack 的 `common.tf` 一致）。env 是 `dev`、`prod`。
7. **`scripts/validate.sh` 已經會跑範本的 `check-ssm-contract.sh` 與 shellcheck**，範本目錄裡 stack 以外的檔案一改，那個範本的 stack 全部重跑（`--changed-since`）。

## 3. 決策

使用者拍板（2026-10-24）：

| # | 決策 | 選項 |
|---|---|---|
| D1 | 算出來的 key | **樣式比對**：`${...}` 當萬用字元；純靜態、不讀 tfvars。代價是抓不到「某個服務名稱沒有被發布」這種只有帶入 tfvars 才知道的錯 |
| D2 | apply 順序的來源 | **新增 `stacks.sh`**，ORDER 寫在裡面，檢查與使用者共用 |
| D3 | 腳本放哪 | **每份範本各一份**：放在 `templates/project-infra/infra/terraform/`，範本複製出去就帶著走；example2、example3 不動 |

照前幾版慣例定下的判斷（審閱時可以推翻）：

| # | 判斷 | 理由 |
|---|---|---|
| K1 | 讀取掃描範圍是 stack 的所有 `.tf`，只認第一段是 ORDER 裡 stack 名稱的 `"<stack>/<key>"` 字串 | 涵蓋 `ssm-inputs.tf` 以外的 `ssm-read` 呼叫（§2 第 3 點），又排除 `"runtime/${r}"` 這類字串 |
| K2 | 種類：在名稱以 `lists` 結尾的 map 或 `merge(...)` 裡的讀取（`ssm_input_lists`、`ssm_agent_lists`、`lists = ...`）當 `StringList`，其他都當 `String`；發布端 `published_lists` 的 key 是 `StringList` | F2 實作時發現 `agent` 用 `ssm_agent_lists`，只認 `ssm_input_lists` 會誤判 |
| K3 | 樣式涵蓋的判定：把讀的樣式的每個 `${...}` 換成 `x`，看能不能被發布樣式轉成的 regex（`${...}` → `[a-z0-9_]+`）整段比中 | 簡單、可預測；例如 `role_agent_x_execution_arn` 比得中 `role_[a-z0-9_]+_arn` |
| K4 | `stacks.sh` 從 example2 改寫，拿掉 bridge、外部共用 env；保留 `--dry-run`、`--yes`、`--` 傳參 | 三份範本操作一致；不加 example2 沒有的功能 |
| K5 | `stacks.sh` 不寫自己的測試，只在驗收時用 `--dry-run` 檢查指令與順序 | example2 的 `stacks.sh` 也沒有測試；邏輯只是依 ORDER 組指令 |

## 4. `check-ssm-contract.sh`

從 example2 的腳本改寫：

- ORDER 從 `stacks.sh` 單行的 `ORDER=(...)` 解析（跟 example2 同一套）。
- **發布**：解析每個 stack 的 `ssm-outputs.tf`：
  - `published_strings`／`published_lists` 第一層寫死的 key（同 example2）；
  - `merge(...)` 裡 `{ for ... : "<樣式>" => ... }` 的字串樣式，記成「樣式 key」；
  - `# planned_strings:`／`# planned_lists:` 註解（同 example2，保留給還沒有 resource 的 stack）。
- **讀取**：掃描 stack 的所有 `.tf`，取出 `"<stack>/<key 或樣式>"`，第一段要是 ORDER 裡的 stack；`${...}` 可以含引號與括號（例如 `${replace(r, "-", "_")}`），解析時要處理巢狀。
- **檢查 1**：每個讀取，在 ORDER 裡比讀取 stack 更早的那個發布 stack，要有寫死的 key 相同，或有樣式涵蓋它（K3），而且種類一致。不通過時印出讀取的檔案與行號、要找的 key、發布 stack 實際發布的 key 與樣式。
- **檢查 2**：每個 env，各 stack `envs/<env>.tfvars` 裡的 `project`、`env`、`aws_region`、`expected_account_id` 必須一致，`env` 等於檔名。沒寫的 key 略過；目前各 stack 的 tfvars 都沒寫 `aws_region`（用 `common.tf` 的預設），寫了才會比對。
- 跟 example2 一樣，失敗時 exit 1，`validate.sh` 會把它算成靜態規則失敗。

## 5. `stacks.sh`

用法跟 example2 相同：

```
stacks.sh <env> <stack|all> <init|validate|plan|apply|destroy|output> [--yes] [--dry-run] [-- <terraform 參數>...]
```

- ORDER：`foundation containerimage network iam-base data agent iam-app loadbalancer application`（README〈apply 順序〉的表）。
- `init` 帶 `-backend-config=envs/<env>.tfbackend`；`plan`／`apply`／`destroy` 帶 `-var-file=envs/<env>.tfvars`。這些是使用者自己執行時才會跑的，驗證時一律 `--dry-run`。
- `all` 依 ORDER 跑，`destroy` 反向。

## 6. 文件

- `templates/project-infra/infra/README.md`：〈apply 順序〉說明 `stacks.sh` 與 ORDER；新增〈SSM 合約檢查〉，寫兩項檢查、樣式比對的規則與限制（§7）。
- `docs/guides/project-infra-standard.md`：提到 `stacks.sh` 與合約檢查。

## 7. 風險與限制

| 風險 | 影響 | 處理 |
|---|---|---|
| 樣式比對太寬（D1） | 讀 `sg_${k}_id` 時，`network` 實際上沒為某個服務發布，檢查也會通過 | README 寫明限制；這類錯在 `terraform plan` 時 `ssm-read` 會讀不到參數而失敗 |
| HCL 寫法改變，解析失敗 | 誤判或漏判 | 腳本只支援 README 寫明的格式；突變測試涵蓋每種寫法；看不懂的寫法直接報錯，不默默略過 |
| 客戶自管模式 | 客戶自管的 stack 不存在，key 由客戶發布 | 檢查的是範本本身（所有 stack 都在）；客戶 repo 的情境照 example2 的做法不特別處理 |
| `stacks.sh` 被拿去對真實環境 apply | 這是給使用者的工具 | 驗證只用 `--dry-run`；腳本本身不在 CI 執行 terraform |
