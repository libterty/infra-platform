# infra-platform v4 實作流程：example3

> 狀態：C0、C1、C1r 完成（2026-10-22），下一步 C2。這份只講「一步一步怎麼做、每步怎麼驗收」；兩份衝突時以 design-docs.md 為準，回頭改這份。
> 文中路徑除非特別註明，都是 repo 內相對路徑。「design §x」指 design-docs.md 的章節。

## 結論

一個里程碑分 10 個 Phase，每個 Phase 一層 stacked PR（`gh stack`）。順序是：先改 module 並發版（C1、C1r），再把 example2 原樣複製成 example3（C2），之後一個 stack 一個 stack 從 ECS 換成 EKS（C3–C7），最後整理文件與驗證紀錄（C8）。

C1r 發版、HCP 確認讀得到之後，C3 以後的範本 PR 才開始，因為範本的 CI 要從 HCP 抓 module。

一次做一個 Phase，主 agent 自己重跑驗收通過後 commit 並 `gh stack submit`，才進下一個；每個 Phase 結束先跟使用者確認，再往下。一個 module 一個 commit。

## 限制（每個 Phase、每個 subagent 都適用）

- Terraform 只准跑 `init -backend=false` 與建在它上面的 `validate`、搭配 `mock_provider` 的 `test`；`scripts/validate.sh` 就是這樣跑的。
- 不准連 AWS 或任何 Kubernetes 叢集；不准 `plan`、`apply`、帶 `-backend-config` 的 `init`、`helm install`、`kubectl`。`helm lint` 與 `helm template` 可以。
- 不准跑 `terraform providers lock`。`eks-addons` stack 的 helm lock hash 由使用者在自己的終端機產生（design E13）。
- code、tfvars、tests、註解、commit message 只出現 `dev`、`sit` 兩個環境名稱。
- example3 只能帶 example2 已有的字串；每個 Phase 結束做一次來源字串反向比對（[`../v2/integration-playbook.md`](../v2/integration-playbook.md)）。
- 佔位值：帳號 `111111111111`、網段 `10.10.0.0/16`、網域 `example.com`。
- example2 不能有任何變動。每個 Phase 驗收都要確認 `git diff main -- templates/example2` 是空的。
- `stacks.sh` 的 ORDER 只列已經存在的 stack 目錄。
- commit 在 feature branch 上做，不推 `main`；合併、發版、HCP 登記之前先問使用者。

## Phase 表

| Phase | 內容 | 狀態 | commit |
|---|---|---|---|
| C0 | v4 設計文件與實作流程 | 完成：第二版審過並合併（#56） | `19cc525` |
| C1 | module：`eks-cluster` 0.2.0、`eks-addons` 0.2.0、`eks-iam-policies` 0.2.0、`iam-role` 0.4.0、新 module `eks-workload-alarms` 0.1.0 | 完成（#57）：iam-role 68、eks-iam-policies 48、eks-workload-alarms 22、eks-cluster 132、eks-addons 116 個 run 全過；4 個本地 chart 經 helm lint 與 template；4 個突變都被測試抓到；`validate.sh` 會跑 `tests/check-*.sh` | `bd6650b` |
| C1r | C1 合併、發版、HCP 登記並確認讀得到 | 完成：5 個 tag 與 GitHub Release；`eks-workload-alarms` 已登記；HCP 上 5 個新版本從消費端抓下來跟 tag 相同 | `995bb05` |
| C2 | example2 原樣複製成 example3，只改 README 裡的路徑與範本名稱 | 未開始 | — |
| C3 | `network`（vpc 0.2.0、subnet tag、`node` SG、`app` SG 規則、endpoint、runner 的來源）、`iam`（新增 EKS 的 role，ECS role 先保留） | 未開始 | — |
| C4 | `eks-cluster` stack；ORDER 加入 `eks-cluster`；EKS 合約 | 未開始 | — |
| C5 | `eks-addons` stack；ORDER 加入 `eks-addons`（helm lock 由使用者產生） | 未開始 | — |
| C6 | `application` 改成部署合約、範例 chart；舊 key 先保留 | 未開始 | — |
| C7 | `loadbalancer` 的 `canary`（預設關閉）、`postdeploy` 改用 `eks-workload-alarms`；所有 consumer 切換後拿掉 ECS 的 role、key 與 module | 未開始 | — |
| C8 | README、保密比對、全量 `validate.sh`；分開記錄「靜態驗證通過」與「雲端整合待驗證」 | 未開始 | — |

## 每個 Phase 的做法與驗收

### C1：module

先派唯讀 planner 對照文件確認，結果跟設計衝突的先回來問使用者：

- `eks-cluster`：Auto Mode 不帶 node role、`node_pools = []` 的組合；EC2 類型 access entry 關聯 `AmazonEKSAutoNodePolicy` 的 provider 寫法。
- `amazon-cloudwatch-observability` Helm chart：要固定的版本、Container Insights（enhanced observability）與 Fluent Bit 的設定、關閉 Application Signals 的參數、CloudWatch agent 與 Fluent Bit 各自的 ServiceAccount（design W2、W3）。
- KEDA：chart 版本、`aws-cloudwatch` scaler 的 `metricType` 實際行為、Pod Identity 的 TriggerAuthentication 寫法。
- Container Insights：`pod_number_of_container_restarts` 是增量還是累計值、`PodName` 維度在 Deployment 上的值（design §10）。

每個 module 照 TDD 做：先寫會失敗的 `terraform test`，再實作。

- `eks-cluster` 0.2.0：design §5 的三項；既有 tests 不改就要全過。
- `eks-addons` 0.2.0：本地 chart 的 NodeClass 必須同時有 Pod subnet 與 Pod SG（測試斷言兩者一起出現或一起不出現）；`system` 的 NetworkPolicy 涵蓋 Kubernetes API、UDP 與 TCP 53、webhook、metrics、AWS API。
- `eks-workload-alarms` 0.1.0：design §10 每一條規則的 metric、dimensions、統計、period、missing-data 都有測試斷言。

驗收：

- `scripts/validate.sh modules/<module>` 全過；本地 chart 經 `helm lint`、`helm template`。
- 新 module 的 `release-please-config.json` 登記好（`initial-version: 0.1.0`），README 的 module 表更新。
- 一個 module 一個 commit；破壞性變更用 `feat!` 並寫 `BREAKING CHANGE`。

### C1r：發版

照 [`../../guides/releasing-modules.md`](../../guides/releasing-modules.md)：合併 stack、release PR 逐一看 diff（同時有多個 release PR 時照〈同時有多個 release PR〉的步驟）、確認 tag 與 GitHub Release。新 module 照 [`../../guides/hcp-registry-setup.md`](../../guides/hcp-registry-setup.md) §3 登記，§4 從消費端抓一次確認版本與內容。

C1 的結果：

- 4 個 module 由 subagent 在獨立 worktree 照 TDD 做，主 agent 逐一重跑 `validate.sh`、review diff、做突變測試後才收進 branch。
- LB Controller 3.6.1 的官方 policy 跟 3.6.0 一字不差；`eks-iam-policies` 預設改 3.6.1，3.6.0 仍可指定。
- release PR 的 CHANGELOG 多了一條 `**eks:** v4 C1 module changes for example3`：PR 標題是 Conventional Commit 格式，merge commit 的內文帶到它，release-please 把它算進每個 module。重建 release PR 的 branch 時刪掉；`releasing-modules.md` 補上提醒。

### C2：複製

`templates/example2` 整個複製成 `templates/example3`。只改 README 與文件裡指向自己路徑的地方；Terraform 內容一字不改。

驗收：`scripts/validate.sh templates/example2/infra/terraform/*/ templates/example3/infra/terraform/*/` 全過；`check-ssm-contract.sh` 兩邊都過；example2 無變動。

### C3：network、iam

- `network`：design §6 的 `network` 那一列，加上 design §7 的 runner 來源（tfvars 給 SG 或 CIDR，建控制平面 443 的規則）。`app` SG 新增的規則要寫測試斷言（來源、port、方向）。依 tfvars 的上限算一次 design K2 的 IP 預算。
- `iam`：新增 design §8.1 的 `iam` role；ECS role 先保留，讓合約在這個 Phase 仍然成立。

驗收：example3 全量 `validate.sh`；`check-ssm-contract.sh`；example2 無變動。

### C4：eks-cluster stack

- 叢集：private endpoint、Auto Mode（`node_pools = []`、不指定 node role）、secrets 加密。
- access entry：node role 的 EC2 entry（`AmazonEKSAutoNodePolicy`）、叢集管理者、`eks-addons` 的 apply 身分、CI 部署身分（限 `app_namespace`）。principal 從 tfvars 給，不能用空字串的 `deploy_role_arn` 代替。
- Pod Identity association：api、worker、LB Controller、KEDA operator、CloudWatch 採集元件。
- 發布 design §8.1 的 `eks-cluster` key，含 `contract_version`；JSON 欄位用 `jsondecode` 斷言。
- ORDER 只加入 `eks-cluster`（`eks-addons` 目錄在 C5 才建立）。

驗收：同 C3，另外測 access entry 的範圍（CI 只有 namespace 範圍、node entry 是 EC2 類型）。

### C5：eks-addons stack

- helm provider 從 SSM 讀 endpoint 與 CA，用 `aws eks get-token`。
- 安裝順序（用 `depends_on` 明確串起來，不靠隱含相依）：
  1. namespace、NodeClass（`app`、`system`）、NodePool
  2. NetworkPolicy controller 的 ConfigMap、`system` 的 NetworkPolicy
  3. controller：AWS Load Balancer Controller、KEDA、CloudWatch 採集
  4. 應用程式要用的 CRD（TargetGroupBinding、ScaledObject）由 3 的 controller 帶進來；`eks-addons` 不建任何應用程式的 CR
- CloudWatch 採集的 DaemonSet 帶能容忍 `app` 與 `system` 兩個 pool 的 toleration（design K3）。
- ORDER 加入 `eks-addons`。
- 跟使用者要 helm lock hash：給一行 `terraform providers lock -platform=darwin_arm64 -platform=linux_amd64` 指令，請使用者用 `!` 在這個 session 跑。

驗收：同 C3；`mock_provider "helm"` 與 `"aws"` 的測試斷言安裝順序與 toleration。

### C6：application 與範例 chart

- `application` 不建資源，發布 design §8.1 的 `application` 新 key。舊的 `cluster_name`、`*_service_name`、`*_log_group_name` **先保留**，因為 C7 之前 `postdeploy` 還在讀。
- 範例 chart 放在 `templates/example3/deploy/charts/app/`：Deployment、ServiceAccount（名稱讀 SSM）、Service、TargetGroupBinding（`elbv2.k8s.aws/v1beta1`，不帶 `networking`）、ScaledObject 與 TriggerAuthentication（design §9 的指標契約）、`app` 的 NetworkPolicy（放行 ALB、CoreDNS 的 UDP 與 TCP 53、DB proxy、Redis、AWS API）。
- `bridge` 加入新 key，舊 key 也先保留。

驗收：同 C3；`helm lint`、`helm template` 通過；新 key 的 JSON 欄位有 `jsondecode` 斷言。

### C7：loadbalancer、postdeploy、拿掉 ECS

- `loadbalancer`：`canary` 預設 `null`。測試涵蓋 design §6.1 列的四種情況。
- `postdeploy`：`eks-workload-alarms`；`stream-alarms.tf` 照搬；log 告警改看 Container Insights 的 application log group。
- 所有 consumer 都切到新 key 之後，拿掉 `iam` 的 ECS role 與權限、`bridge` 與 `application` 的舊 key。

驗收：同 C3；`grep` 確認 example3 沒有 `ecs-*` module、ECS 的 SSM key 與 `ecs-tasks.amazonaws.com`（README 的差異說明除外）。

### C8：收尾

- README：apply 順序、design §7 的執行環境與前提、SSM 合約表（含 Type 與 JSON 欄位）、跟 example2 的差異、design §6.1 的 canary runbook、design §11 的未確認事項。
- 保密：對 example3 全目錄做來源字串反向比對。
- 全量 `scripts/validate.sh`。
- 驗證紀錄分兩張表：
  - **靜態驗證通過**：`validate.sh`、`check-ssm-contract.sh`、`helm lint`、`helm template`、保密比對。
  - **雲端整合待驗證**（要真實帳號，這個里程碑不做）：node 加入叢集、DNS（實際 resolver、UDP 與 TCP 53）、Pod Identity 取得憑證與 secret、TargetGroupBinding 註冊 target 以及刪除後保留 target group、KEDA 依三個指標擴縮與縮容、CloudWatch 採集涵蓋 `app` 與 `system` node、每條告警能觸發、no-NAT 時的 endpoint 路徑、canary 權重與斷路器的完整流程。

驗收：全量通過；使用者審過 README 與兩張驗證表。
