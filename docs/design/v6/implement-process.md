# infra-platform v6 實作流程：project-infra 的 SSM 合約檢查

> 狀態：F0（設計）審閱中。這份只講「一步一步怎麼做、每步怎麼驗收」；兩份衝突時以 design-docs.md 為準，回頭改這份。
> 文中路徑除非特別註明，都是 repo 內相對路徑。「design §x」指 design-docs.md 的章節。project-infra 的路徑都在 `templates/project-infra/infra/terraform/` 底下。

## 結論

分 4 個 Phase，每個 Phase 一層 stacked PR（`gh stack`）。先補 `stacks.sh`（F1），再寫檢查腳本（F2），最後改文件（F3）。不改任何 module，所以不發版。

## 限制

- 不碰 AWS：不准 `terraform plan`、`apply`、帶 backend 的 `init`、任何 `aws` 指令；`stacks.sh` 驗證時一律 `--dry-run`。
- stack 的 `.tf` 與 tfvars 一行都不改；example2、example3 不動。
- 腳本要過 `bash -n` 與 shellcheck（`validate.sh` 會跑）；用 bash，不依賴 zsh。
- commit 在 feature branch 上做，不推 `main`。

## Phase 表

| Phase | 內容 | 狀態 | commit |
|---|---|---|---|
| F0 | v6 設計文件與實作流程 | 審閱中 | — |
| F1 | `stacks.sh` | 未開始 | — |
| F2 | `check-ssm-contract.sh` | 未開始 | — |
| F3 | README 與指南 | 未開始 | — |

## 每個 Phase 的做法與驗收

### F1：`stacks.sh`

做法：從 `templates/example2/infra/terraform/stacks.sh` 改寫（design §5），拿掉 bridge 與外部共用 env，ORDER 照 README〈apply 順序〉。

驗收：

- `bash -n`、shellcheck 通過。
- `--dry-run`：`stacks.sh dev all plan --dry-run` 依 ORDER 印出 9 個 stack 的指令，每個都帶 `-var-file=envs/dev.tfvars`；`destroy` 反向；`init` 帶 `-backend-config=envs/dev.tfbackend`；未知 stack、未知動作、缺參數都以 exit 2 結束並印用法。
- ORDER 跟 README 的表一致，而且 ORDER 裡每個 stack 目錄都存在。

### F2：`check-ssm-contract.sh`

做法：design §4。

驗收：

- 在現有 project-infra 上通過，列出檢查了幾個 stack、幾個讀取、幾個 env。
- `scripts/validate.sh templates/project-infra/infra/terraform/foundation` 會跑到它（輸出有 `OK check-ssm-contract` 的 project-infra 那一行）。
- 突變（每一種都要讓檢查失敗，訊息指到正確的檔案與 key）：
  1. 寫死的讀取改成不存在的 key；
  2. 讀取改成 ORDER 較晚的 stack 發布的 key；
  3. `ssm_input_lists` 裡讀一個 `String` key；
  4. 算出來的讀取改成沒有樣式涵蓋的樣式（例如 `network/sg_${k}_idx`）；
  5. 拿掉發布端的一個樣式；
  6. `application/agent.tf` 這類 `ssm-inputs.tf` 以外的讀取改成不存在的 key；
  7. 某個 stack 的 `envs/dev.tfvars` 改掉 `aws_region`；
  8. 某個 tfvars 的 `env` 跟檔名不同；
  9. ORDER 列了不存在的 stack。
- 反向：`"runtime/${r}"` 這類非 stack 字串不被當成讀取。

### F3：文件

做法：design §6。

驗收：README 的 ORDER 說明與 `stacks.sh` 一致；全量 `scripts/validate.sh` 通過。
