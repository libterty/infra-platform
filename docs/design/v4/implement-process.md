# infra-platform v4 實作流程：example3

> 狀態：草案，等 [`design-docs.md`](./design-docs.md) 審過才開始。這份只講「一步一步怎麼做、每步怎麼驗收」；兩份衝突時以 design-docs.md 為準，回頭改這份。
> 文中路徑除非特別註明，都是 repo 內相對路徑。「design §x」指 design-docs.md 的章節。

## 結論

一個里程碑分 9 個 Phase，每個 Phase 一層 stacked PR（`gh stack`）。順序是：先改 module 並發版（C1），再把 example2 原樣複製成 example3（C2），之後一個 stack 一個 stack 從 ECS 換成 EKS（C3–C7），最後整理文件與全量驗證（C8）。

C1 的 module 要發版、HCP 登記並讀到新版之後，C3 以後的範本 PR 才能開始，因為範本的 CI 要從 HCP 抓 module。

一次做一個 Phase，主 agent 自己重跑驗收通過後 commit 並 `gh stack submit`，才進下一個；每個 Phase 結束先跟使用者確認，再往下。一個 module 一個 commit。

## 限制（每個 Phase、每個 subagent 都適用）

- Terraform 只准跑 `init -backend=false` 與建在它上面的 `validate`、搭配 `mock_provider` 的 `test`；`scripts/validate.sh` 就是這樣跑的。
- 不准連 AWS 或任何 Kubernetes 叢集；不准 `plan`、`apply`、帶 `-backend-config` 的 `init`、`helm install`、`kubectl`。`helm lint` 與 `helm template` 可以。
- 不准跑 `terraform providers lock`。`eks-addons` stack 的 helm lock hash 由使用者在自己的終端機產生（design E13）。
- code、tfvars、tests、註解、commit message 只出現 `dev`、`sit` 兩個環境名稱。
- example3 只能帶 example2 已有的字串；每個 Phase 結束做一次來源字串反向比對（[`../v2/integration-playbook.md`](../v2/integration-playbook.md)）。
- 佔位值：帳號 `111111111111`、網段 `10.10.0.0/16`、網域 `example.com`。
- example2 不能有任何變動。每個 Phase 驗收都要確認 `git diff main -- templates/example2` 是空的。
- commit 在 feature branch 上做，不推 `main`；合併、發版、HCP 登記之前先問使用者。

## Phase 表

| Phase | 內容 | 狀態 | commit |
|---|---|---|---|
| C0 | v4 設計文件與實作流程 | 草案，等審閱 | — |
| C1 | module：`eks-addons` 0.2.0、`eks-iam-policies` 0.2.0、`eks-workload-alarms` 0.1.0，依 §9 W2 決定 `iam-role` 0.4.0，`eks-cluster` 查證後才決定要不要改 | 未開始 | — |
| C1r | C1 合併、發版、HCP 登記並確認讀得到 | 未開始 | — |
| C2 | example2 原樣複製成 example3，只改 README 裡的路徑與範本名稱 | 未開始 | — |
| C3 | `network`（vpc 0.2.0、subnet tag、`node` SG、`app` SG 規則、endpoint）、`iam`（新增 EKS 的 role，ECS role 先保留） | 未開始 | — |
| C4 | `eks-cluster` stack、`stacks.sh` 的 ORDER、SSM 合約 | 未開始 | — |
| C5 | `eks-addons` stack（helm lock 由使用者產生） | 未開始 | — |
| C6 | `application` 改成部署合約、範例 chart；拿掉 `iam` 與 `bridge` 的 ECS role 與 key | 未開始 | — |
| C7 | `loadbalancer` 的 `canary`（預設關閉）、`postdeploy` 改用 `eks-workload-alarms` | 未開始 | — |
| C8 | README（apply 順序、合約表、執行環境、runbook、已知限制）、保密比對、全量 `validate.sh` | 未開始 | — |

## 每個 Phase 的做法與驗收

### C1：module

先派唯讀 planner 對照 AWS 文件確認：

- `eks-cluster` 的 `auto_mode.node_pools = []` 能不能關掉內建 NodePool，輸出有沒有 cluster SG 與 service CIDR。
- `amazon-cloudwatch-observability` Helm chart 的版本、參數、需要的 IAM。
- KEDA 讀 CloudWatch 指標需要的 IAM 動作與 Pod Identity 的設定方式。
- Container Insights 的 pod 指標名稱與維度（給 `eks-workload-alarms`）。

查證結果有跟設計衝突的，先回來問使用者，再動手。每個 module 照 TDD 做：先寫會失敗的 `terraform test`，再實作。

驗收：

- `scripts/validate.sh modules/<module>` 全過；本地 chart 經 `helm lint`、`helm template`。
- 新 module 的 `release-please-config.json` 登記好（`initial-version: 0.1.0`），README 的 module 表更新。
- 一個 module 一個 commit；破壞性變更用 `feat!` 並寫 `BREAKING CHANGE`。

### C1r：發版

照 [`../../guides/releasing-modules.md`](../../guides/releasing-modules.md)：合併 stack、release PR 逐一看 diff（同時有多個 release PR 時照〈同時有多個 release PR〉的步驟）、確認 tag 與 GitHub Release。新 module 照 [`../../guides/hcp-registry-setup.md`](../../guides/hcp-registry-setup.md) §3 登記，§4 從消費端抓一次確認版本與內容。

### C2：複製

`templates/example2` 整個複製成 `templates/example3`。只改 README 與文件裡指向自己路徑的地方；Terraform 內容一字不改。

驗收：`scripts/validate.sh templates/example2/infra/terraform/*/ templates/example3/infra/terraform/*/` 全過；`check-ssm-contract.sh` 兩邊都過；example2 無變動。

### C3：network、iam

- `network`：design §6 的 `network` 那一列。`app` SG 新增的規則要寫測試斷言（來源、port、方向）。
- `iam`：新增 design §7 的 `iam` role；ECS role 先保留，讓合約在這個 Phase 仍然成立。CloudWatch agent 的 policy 依 W2 的決定。

驗收：example3 全量 `validate.sh`；`check-ssm-contract.sh`；example2 無變動。

### C4：eks-cluster stack

- 叢集：private endpoint、Auto Mode（`node_pools = []`）、secrets 加密。
- access entry：叢集管理者、`eks-addons` 的 apply 身分、CI 部署身分（限 `app_namespace`）。principal 從 tfvars 給，不能用空字串的 `deploy_role_arn` 代替。
- Pod Identity association：api、worker、LB Controller、KEDA、CloudWatch agent。
- 發布 design §7 的 `eks-cluster` key，含 `contract_version`。
- `stacks.sh` 的 ORDER 加上 `eks-cluster`、`eks-addons`（design E11）。

驗收：同 C3，另外測 access entry 的範圍（CI 只有 namespace 範圍）。

### C5：eks-addons stack

- helm provider 從 SSM 讀 endpoint 與 CA，用 `aws eks get-token`。
- NodeClass：`app`（node SG＋cluster SG；Pod subnet＋`app` SG；`networkPolicy` 依 W4）與 `system`。NodePool 各一組。
- 啟用 NetworkPolicy controller、建 namespace、裝 LB Controller、KEDA、CloudWatch 採集。
- 跟使用者要 helm lock hash：給一行 `terraform providers lock -platform=darwin_arm64 -platform=linux_amd64` 指令，請使用者用 `!` 在這個 session 跑。

驗收：同 C3；`mock_provider "helm"` 與 `"aws"` 的測試斷言 NodeClass 的 Pod subnet 與 Pod SG 一起出現。

### C6：application 與範例 chart

- `application` 不建資源，只發布 design §7 的 `application` key。
- 範例 chart 放在 `templates/example3/deploy/charts/app/`：Deployment、ServiceAccount（名稱讀 SSM）、Service、TargetGroupBinding（`elbv2.k8s.aws/v1beta1`，不帶 `networking`）、ScaledObject、NetworkPolicy（放行 ALB、CoreDNS、DB proxy、Redis 與 endpoint）。
- 拿掉 `iam` 的 ECS role 與權限、`bridge` 的 ECS key。

驗收：同 C3；`helm lint`、`helm template` 通過；`grep` 確認 example3 沒有 `ecs` 相關的 module 與 key（README 的歷史說明除外）。

### C7：loadbalancer、postdeploy

- `loadbalancer`：`canary` 預設 `null`，給了才建第二個 target group、加權 rule 與 `lb-traffic-breaker`。測試涵蓋關閉（零資源）與開啟兩種情況。
- `postdeploy`：`eks-workload-alarms`；log 告警改看 Container Insights 的 log group。

驗收：同 C3。

### C8：收尾

- README：apply 順序、哪些 stack 要在 VPC 內執行（只有 `eks-addons` 與 CI 的 Helm）、runner 需要的 access entry、SSM 合約表、跟 example2 的差異、design §10 的未確認事項。
- 保密：對 example3 全目錄做來源字串反向比對。
- 全量 `scripts/validate.sh`。

驗收：全量通過；使用者審過 README。
