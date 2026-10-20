# infra-platform v2 實作流程：example2

> 狀態：v2 完成（A1–A5、B1–B6 都已完成；PR-A 已合併發版，PR-B 待使用者決定合併）。設計以 [`design-docs.md`](./design-docs.md) 為準；這份只講「一步一步怎麼做、每步怎麼驗收」。兩份衝突時，以 design-docs.md 為準，回頭改這份。
> 2026-10-20 改寫過 git 歷史，拿掉參考專案的細節（PR #15）：文中的 commit hash 都已換成改寫後的值；只改文件的 commit 在改寫後沒有內容差異而被併掉，表中標「已併入」。
> 文中路徑除非特別註明，都是 repo 內相對路徑。「design §x.y」指 design-docs.md 的章節。

## 結論

分兩個 PR、12 個 Phase。PR-A 是 module（A1–A5），PR-B 是範本（B1–B6）。PR-A 合併、發版、在 HCP 登記之後，PR-B 的 stack 才抓得到新 module，才能 validate。B1（`validate.sh` 支援多範本）不依賴新 module，可以跟 PR-A 平行做，但跟 PR-B 一起合併。

一次做一個 Phase，主 agent 自己重跑驗收通過後 commit，才進下一個；每個 Phase 結束先跟使用者確認，再往下。**一個 module 一個 commit**。

## 限制（每個 Phase、每個 subagent 都適用）

- Terraform 只准跑 `init -backend=false`（從 HCP 抓 module），以及建在它上面的 `validate`、搭配 `mock_provider` 的 `test`；`scripts/validate.sh` 就是這樣跑的，而且會清掉 AWS 環境變數。
- 不准連 AWS；不准 `plan`、`apply`、帶 `-backend-config` 的 `init`、`terraform providers lock`；不准跑 `stacks.sh` 的 `init`、`plan`、`apply`、`destroy`。
- lock 檔不要在 macOS 上單獨 `init -backend=false` 產生（只會有 darwin 的 `h1:`）；新 provider 的段落從 repo 裡已有兩個 `h1:` 的 lock 檔複製。S10 會擋。
- code、tfvars、tests、註解、commit message 只出現 `dev`、`sit` 兩個環境名稱。
- 不從來源專案複製任何 tfvars、tfbackend；所有值都重新寫成佔位值。
- 去機密掃描照 [`integration-playbook.md`](./integration-playbook.md) §4；真名 pattern 在本機的 `docs/design/v2/private/`，不進版控。
- commit 在 feature branch 上做，不推 `main`；push、打 tag、建 Release、HCP 登記之前先問使用者。

## Phase 表

| Phase | PR | 內容 | 狀態 | commit |
|---|---|---|---|---|
| 0 | A | v2 設計文件、實作流程、整合流程 | 已完成 | 1：`9418da7` |
| A1 | A | 擴充 6 個既有 module 到 0.2.0：`iam-role`、`s3-bucket`、`rds`、`alb`、`ecs-service`、`log-metric-alarm` | 已完成：主 agent 重跑 `validate.sh` 16 個目錄全過，432 個 run（原本 343，新增 89），既有 test 檔零修改；差異已寫回 design §4.1 | 6：`0e7e132`、`921a294`、`05c66ee`、`f5e0bca`、`0fd8d6e`、`79dc3ac` |
| A2 | A | 新 module：`metric-alarm`、`vpc-peering`、`ec2-bastion`、`lambda-function` | 已完成：主 agent 重跑 `validate.sh` 9 個目錄全過，218 個 run；lambda-function 的 tests 拆成 4 個檔（都在 800 行內）；差異已寫回 design §4.2 | 4：`fc3e107`、`2e367cc`、`cad82d2`、`b2eb833` |
| A3 | A | 新 module：`elasticache-redis`、`waf-web-acl` | 已完成：主 agent 重跑 `validate.sh` 4 個目錄全過，146 個 run；差異已寫回 design §4.2 | 2：`f8e92ce`、`e3a302c` |
| A4 | A | 共用設定：release-please config 與 manifest、README module 表與徽章、CHANGELOG | 已完成：manifest 19 個 `0.1.0`、7 個 `0.1.1`、6 個 `0.2.0`；主 agent 全量 `validate.sh` 80 個目錄、2,046 個 test run 全過（5 分 24 秒）；PR-A 整段去機密掃描零命中。另補已發佈 29 段 CHANGELOG 的日期（`5d087ac`） | 1：`5de867c` |
| A5 | — | （使用者確認後）合併 PR-A、打 12 個 tag、補 GitHub Release、HCP 登記 6 個新 module | 已完成：PR #5 合併為 `18f48a6`，12 個 annotated tag 打在 `18f48a6`，12 個 GitHub Release（不設 latest）；HCP 登記 6 個新 module。一次推 12 個 tag 沒觸發 GitHub webhook，6 個已登記的 module 沒收到 `0.2.0`，逐一刪掉重新登記後補上。暫存目錄 `init -backend=false` 抓到 32 個 module，抽 4 個跟 tag 逐檔比對一致 | — |
| B1 | B | `validate.sh` 與 `ci.yml` 支援多份範本 | 已完成：主 agent 重跑全量 80 個目錄、2,046 個 run，跟改之前相同；scratchpad fixture 的 5 個情境，舊版全部漏掉，新版抓到 S5 不一致、合約檢查失敗、`.sh` 語法錯誤。範本的 `*.sh` 有裝 shellcheck 時，警告也算失敗；外部客戶 repo 的 stack 仍對應到 project-infra | 1：`69f8ea7` |
| B2 | B | example2 骨架：11 份 `common.tf`、`providers.tf`、`versions.tf`，envs 佔位檔，`stacks.sh`，`check-ssm-contract.sh` | 已完成：`validate.sh templates/example2/infra/terraform` 11 個目錄、99 個 run 全過（每個 stack 7 個 common 測試加 dev、sit 兩份 tfvars 各 1 個）；project-infra 仍是 9 個目錄全過。合約骨架：讀的 key 寫成真的 `ssm-inputs.tf`，發布的 key 因為還沒有資源可接，只用 `# planned_strings:`／`# planned_lists:` 註解列出，不放假值。差異寫在 design §5.7 | 1：`a4713f5` |
| B3 | B | 前段 stack：`containerimage`、`foundation`、`network`、`database`、`iam` | 已完成：主 agent 重跑 `validate.sh templates/example2/infra/terraform` 11 個目錄、184 個 run 全過；去機密掃描零命中。R2 沒有循環（graph test 不 mock `rds` 也通過）。使用者決定：secret key 以內容命名、兩個 import Lambda 各一個 role（同步改後段骨架的 key 名稱）。差異與後段命名規則見 design §5.7、§5.8 | 10：`db56cef`、`310b013`、`db71db6`、`53e2322`、`a03fae4`、`3b31491`、已併入、`d90c7e7`、`5bf1994`、已併入 |
| B4 | B | `bridge` 與樹 B 合約 | 已完成：主 agent 重跑 `validate.sh templates/example2/infra/terraform` 11 個目錄、191 個 run 全過；照 playbook 完整清單掃描零命中。轉寫 25 個 key（21 個 string、4 個 list），等於後段讀的聯集；guard 擋空字串、subnet 少於 2 個、不合法的 JSON；README 列出給外部發布者的樹 B 合約。差異見 design §5.9 | 2：`f1b874d`、本 commit |
| B5 | B | 後段 stack：`loadbalancer`、`agent`、`application`、`operation`、`postdeploy` | 已完成：主 agent 重跑 `validate.sh templates/example2/infra/terraform` 11 個目錄、299 個 run 全過；lock 檔每個 provider 都有 2 個 `h1:`；用來源專案全部字串反向比對，照抄的文案、metric 名稱、error message、變數名稱都已換掉。使用者決定：補 guardrail-profile 權限、Runtime 經樹 B 接 DB（`db_name`、`stream_shard_count`）、拿掉沒人讀的 key、還原 extract 端 rejected 指標。命名規則對照見 design §5.10。待辦：alb 0.3.0 發佈後拿掉 `format()` 繞法 | 見 git log（`feat/example2-b5`） |
| B6 | B | lock 檔、去機密掃描、範本 README、repo README、guides 更新、全量驗收 | 已完成：新增靜態規則 S10（範本 stack 的 lock 檔每個 provider 至少 2 個 `h1:`；fixture 的單一 `h1:` 舊版不擋、新版擋，兩個 `h1:` 通過，客戶 repo 的 stack 同樣適用）；主 agent 重跑全量 `validate.sh` 91 個目錄、2,346 個 run 全過（7 分 10 秒）；範本 README 補齊各 stack、`stacks.sh`、複製後要改的值、destroy 前的事與已知限制；repo README、兩份 guides 補上 example2，`hcp-registry-setup.md` 的「9 個目錄」指的是 project-infra 的 9 個 stack，實際跑過仍是 9，不用改；整合流程補上這次學到的事 | 見 git log |

## 每個 Phase 的做法與驗收

### A1：擴充既有 module

介面見 design §4.1。每個 module：

1. 先寫新的 tests（RED）：新功能的 run 因為還沒實作而失敗；新 validation 各有正反兩個 run。
2. 寫最小實作讓 tests 通過（GREEN），再整理（REFACTOR）。
3. 既有 tests 一個都不改。
4. CHANGELOG 加 `## 0.2.0（未發布）`，README 補新變數。
5. commit：`feat(<module>): <what>`。

驗收：`scripts/validate.sh modules/<module>` 全過（含 `examples/`）；`git diff` 確認既有 tests 沒有變動。

### A2、A3：新 module

介面與必寫情境見 design §4.2。每個 module 都有 `examples/basic/`、`README.md`、`CHANGELOG.md`（`## 0.1.0（未發布）`）。TDD 步驟同 A1。安全相關的 negative test 不能省：

- `ec2-bastion`：IMDSv2、不配 public IP、root volume 加密。
- `lambda-function`：principal 格式；`s3.amazonaws.com` 沒給 `source_account` 被拒；`latest` 映像被拒；名稱像 secret 的環境變數被拒。
- `vpc-peering`：`0.0.0.0/0` 被拒；CIDR 重疊被拒。
- `waf-web-acl`：body-size 例外沒先把 common rule set 的 `SizeRestrictions_BODY` 設成 count 時被拒；預設遮蔽的 header 有出現在 logging 設定。
- `elasticache-redis`：加密、failover 沒有開關可以關；`cache.t*` 配 autoscaling 被拒。

驗收：`scripts/validate.sh modules/<module>` 全過；`tflint` 零警告。

### A4：共用設定

- `release-please-config.json` 加 6 個 package；`.release-please-manifest.json` 加 6 個 `0.1.0`，6 個擴充的改 `0.2.0`。
- `README.md` 的 module 表加 6 列，徽章照現有格式。
- 跑去機密掃描。

驗收：`scripts/validate.sh modules` 全過；去機密掃描沒有新增命中；PR-A 的 CI 綠燈。

### A5：發版與 HCP 登記

每一步做之前先問使用者：

1. 合併 PR-A 之前，在 PR-A 裡把 12 段 CHANGELOG 標題的「（未發布）」改成預計發版日期（手動打 tag 時 release-please 不會改，見 `docs/guides/releasing-modules.md`）；合併後 `git switch main && git pull`。
2. 從 manifest 讀出 12 個 tag，在合併後的 commit 打 annotated tag，只 push 這 12 個。
3. `gh release create <tag> --notes-file modules/<m>/CHANGELOG.md`，不設 latest。
4. 照 `docs/guides/hcp-registry-setup.md` §3 登記 6 個新 module，等狀態變成 `setup_complete`。
5. 已登記的 module 有沒有收到新 tag：一次推超過 3 個 tag 時 GitHub 不發 webhook，要照 `hcp-registry-setup.md`〈之後的維護〉補。

驗收：照 `hcp-registry-setup.md` §4 在暫存目錄 `terraform init -backend=false` 抓 32 個 module，版本跟 tag 一致。

### B1：`validate.sh` 與 CI 支援多份範本

改法見 design §6。先在 scratchpad 做一個有兩份範本、其中一份 `common.tf` 故意不一致的 fixture，確認 S5 會報錯（RED），再改 `validate.sh`（GREEN）。

驗收：`scripts/validate.sh` 全量跑，project-infra 的目錄數與結果跟改之前相同；`bash -n`、`shellcheck` 通過。

### B2：example2 骨架

- 11 份 `common.tf` 一字不差；`accounts_by_env = { dev, sit }`。
- 每個 stack 的 `envs/dev.*`、`envs/sit.*` 都是佔位值；`.tfbackend` 的 key 符合 `example-<env>/<stack>/terraform.tfstate`。
- `stacks.sh`：ORDER、`EXTERNAL_SHARED_ENVS`、只從 `<stack>/envs/` 讀檔（design §5.5）。
- `check-ssm-contract.sh`：先寫兩個負面 fixture（讀不存在的 key、讀排在後面的 stack 的 key），確認會失敗，再實作。

驗收：S5、S6 通過；`bash -n`、`shellcheck` 通過；`check-ssm-contract.sh` 對負面 fixture 失敗、對骨架通過。

### B3–B5：stack

每個 stack 先寫 `tests/<stack>.tftest.hcl`，斷言 locals 與 module 的輸入、輸出（RED），再寫 module 呼叫（GREEN）。要保留的情境見 design §5.6。B3 的 `database` 要特別看 design §7 R2 的循環依賴。

驗收：`scripts/validate.sh templates/example2/infra/terraform/<stack>` 全過，dev、sit 兩份 tfvars 的 tests 都有跑到；`check-ssm-contract.sh` 通過；這個 Phase 新增的檔案去機密掃描零命中。

### B6：收尾

- lock 檔：每個 provider 段落至少 2 個 `h1:`（S10 檢查），確認 CI 的 `-lockfile=readonly` 能過。
- 範本 README：樹 A／樹 B 合約、外部發布樹 B 要給的 key、apply 順序、環境切換。
- repo README 的範本列表；`docs/guides/hcp-registry-setup.md` 裡驗證的目錄數。
- 去機密掃描全 repo 跑一次；commit message、PR 標題與描述、branch 名稱人工看一次。

驗收：`scripts/validate.sh` 全量通過；去機密掃描零命中；PR-B 的 CI 綠燈；量測 CI 時間，超過 `timeout-minutes` 再調。
