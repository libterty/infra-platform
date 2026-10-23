# infra-platform v4 實作流程：example3

> 狀態：C0–C8 全部完成（2026-10-23）。這份只講「一步一步怎麼做、每步怎麼驗收」；兩份衝突時以 design-docs.md 為準，回頭改這份。
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
| C2 | example2 原樣複製成 example3，只改 README 裡的路徑與範本名稱 | 完成：`git archive` 複製 196 個追蹤中的檔案；README 只改標題、改寫中說明與驗證指令的路徑；兩個範本 22 個 stack 全部通過、`check-ssm-contract.sh` 兩邊都過；example2 無變動 | — |
| C3 | `network`（vpc 0.2.0、subnet tag、`node` SG、`app` SG 規則、endpoint、runner 的來源）、`iam`（新增 EKS 的 role，ECS role 先保留） | 完成：network 43、iam 34 個 run 全過；example3 11 個 stack 與 `check-ssm-contract.sh` 通過；突變（pod trust 不限叢集、api_pod 保留 ECS Exec）都被抓到；example2 無變動 | — |
| C4 | `eks-cluster` stack；ORDER 加入 `eks-cluster`；EKS 合約 | 完成：eks-cluster 22 個 run、bridge 16 個 run 全過；example3 12 個 stack 與 `check-ssm-contract.sh` 通過；9 個突變都被抓到；example2 無變動 | — |
| C5m | `eks-addons` 0.3.0：`aggregate_crd_roles`（design C5-1）；發版、HCP 確認 | 完成：#67 合併；Release run 遇到 GitHub 事件失敗 4 次，恢復後重跑成功；#69 發版，HCP 上的 0.3.0 從消費端抓下來跟 tag 相同 | — |
| C5 | `eks-addons` stack（用 0.3.0）；ORDER 加入 `eks-addons`（helm lock 由使用者產生） | 完成：eks-addons 16 個 run 加 tfvars 2 個全過；example3 13 個 stack（356 個 run）與 `check-ssm-contract.sh` 通過；9 個突變都被抓到；helm 3.3.0 的 lock 由使用者產生；example2 無變動 | — |
| C6 | `application` 改成部署合約、範例 chart；舊 key 先保留 | 完成：application 30 個 run、`check-deploy-values.sh` 通過；example3 13 個 stack（360 個 run）與 `check-ssm-contract.sh` 通過；12 個突變都被抓到；example2 無變動 | — |
| C7 | `loadbalancer` 的 `canary`（預設關閉）、`postdeploy` 改用 `eks-workload-alarms`；所有 consumer 切換後拿掉 ECS 的 role、key 與 module | 完成：example3 13 個 stack（362 個 run）、`check-ssm-contract.sh`、`check-deploy-values.sh` 通過；14 個突變都被抓到；example3 沒有 ECS module、key 與 `ecs-tasks.amazonaws.com`；example2 無變動 | — |
| C8 | README、保密比對、全量 `validate.sh`；分開記錄「靜態驗證通過」與「雲端整合待驗證」 | 完成：README 改寫；example3 全目錄保密比對通過；全量 `validate.sh` 通過；兩張驗證表在 README〈驗證〉 | — |

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

C3 的結果：

- `network`：新增 `node`、`eks_api` 兩個 SG（9 個）。`eks_api` 掛在控制平面 ENI 上，只放行 `k8s_api_sources`（新變數，預設空、不收 0.0.0.0/0）的 443，由 C4 的 `eks-cluster` 以 `security_group_ids` 帶入，避開跨 stack 循環。`node`→`app` 開 `app_port`（kubelet 探測），`app`→`node` 開 TCP 與 UDP 53（CoreDNS）。`app` tier 加 `eks-node`、`eks-pod` tag（值是叢集名稱）。`nat_mode = "none"` 時加 EKS、ECR、STS、ELB、logs、monitoring 的 interface endpoint。新發布 `node_sg_id`、`eks_api_sg_id`、`app_subnet_cidrs`。
- `iam`：iam-role 升 0.4.0；新增 7 個 role。叢集名稱固定是 `<project>-<env>`，Pod Identity role 以 aws:SourceArn 限定這個叢集。叢集 role 的 BlockStorage policy 用 `AmazonEKSBlockStoragePolicy`（v3 留下的兩個名稱之一，真實環境要核對）。LB Controller、KEDA 的 policy 直接用 `eks-iam-policies` 0.2.0 的輸出。新發布 7 個 role ARN；ECS 的 3 個 role 與 key 保留到 C7。

### C4：eks-cluster stack

- 叢集：private endpoint、Auto Mode（`node_pools = []`、不指定 node role）、secrets 加密。
- access entry：node role 的 EC2 entry（`AmazonEKSAutoNodePolicy`）、叢集管理者、`eks-addons` 的 apply 身分、CI 部署身分（限 `app_namespace`）。principal 從 tfvars 給，不能用空字串的 `deploy_role_arn` 代替。
- Pod Identity association：api、worker、LB Controller、KEDA operator、CloudWatch 採集元件。
- 發布 design §8.1 的 `eks-cluster` key，含 `contract_version`；JSON 欄位用 `jsondecode` 斷言。
- ORDER 只加入 `eks-cluster`（`eks-addons` 目錄在 C5 才建立）。

驗收：同 C3，另外測 access entry 的範圍（CI 只有 namespace 範圍、node entry 是 EC2 類型）。

C4 的結果：

- `eks-cluster` stack：kms-key 0.1.0 建 secrets 加密的 key；eks-cluster 0.2.0 建叢集（名稱 `<project>-<env>`，private endpoint，Auto Mode `node_pools = []`、不帶 node role，`security_group_ids` 帶 `eks_api_sg_id`）。access entry 有 node（`EC2`、`AmazonEKSAutoNodePolicy`）、每個管理者、`addons_apply`（叢集管理者）、`ci_deploy`（`AmazonEKSEditPolicy`，限 `app_namespace`）。Pod Identity association 有 api、worker、LB Controller、KEDA、CloudWatch 採集 5 個。發布 design §8.1 的 9 個 key，`contract_version = "1"`。
- 只讀樹 B（design C4-1）：`bridge` 多轉寫 `eks_api_sg_id` 與 7 個 EKS role，README 的樹 B 合約表跟著更新成 34 個 key、apply 順序表加入 `eks-cluster`。
- 測試先後：實作比測試先寫，所以用突變測試補驗。9 個突變都被抓到：node entry 改成 `STANDARD`、CI 改叢集範圍、CI 改 Admin policy、KEDA ServiceAccount、worker 拿到 api 的 role、拿掉 principal 不重複的檢查、叢集名稱、拿掉 `contract_version`、`bridge` 少轉寫一個 key（由 `check-ssm-contract.sh` 抓到）。
- 保密：這個 Phase 改到的 21 個檔案跑過 9 組 pattern，都沒有命中。反向比對命中的都是公開識別，或 example2 原本就有的變數名稱。

### C5m：eks-addons 0.3.0

C4 留下的風險（design §11 第 15 點）在 C5 開始前查 chart 原始碼確認：LB Controller 3.6.1 的 chart 沒有併進 `edit` 的 ClusterRole，也沒有 extraObjects；KEDA 2.21.0 有 `keda:edit`、`keda:view`，但 `rbac.aggregateToDefaultRoles` 預設是 `false`。範本只能呼叫 module，所以先改 module（design C5-1）。

- `aggregate_crd_roles`（預設 `false`）：有裝 LB Controller 時裝本地 chart `crd-role-aggregation`（`depends_on` LB Controller）；有裝 KEDA 時 `set` `rbac.aggregateToDefaultRoles=true`。
- TDD：先寫 `tests/crd-roles.tftest.hcl` 看到失敗，再實作；`check-ordering.sh` 加一條邊。

驗收：`validate.sh modules/eks-addons` 全過、`helm lint` 與 `helm template`（`targetGroupBindings` 開與關）、`check-ordering.sh`、突變測試；發版照 C1r。

C5m 的結果：120 個 run 全過（新增 4 個）；chart 兩種值都通過 lint 與 template；`check-ordering.sh` 通過；4 個突變（KEDA 永遠打開、不看 LB Controller、忽略開關、值寫成 `false`）都被抓到。

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

C5 的結果：

- `eks-addons` stack 讀 `eks-cluster` 的合約與樹 B，設定見 design C5-2 到 C5-6。安裝順序與 CloudWatch 的 toleration 由 module 負責（`check-ordering.sh`、chart 預設值），stack 的測試斷言傳給 module 的 NodeClass、NodePool、placement、NetworkPolicy，以及實際安裝的 release 與各 controller 的 namespace。
- 0.3.0 上 HCP 之前，先把 module 來源暫時指向 repo 路徑，在 scratchpad 的副本裡驗證；上 HCP 之後改用正式來源重跑。
- 突變：system 加 Pod SG、少 node SG、改 `DefaultAllow`、拿掉 taint、`nat_mode` 判斷反過來、關掉 `aggregate_crd_roles`、改 KEDA namespace、node role 傳 ARN、多支援一個合約版本，9 個都被抓到。
- `nat_mode` 不一致時 `check-ssm-contract.sh` 會失敗（以 sit 改成 `none` 實測）。
- lock：先從 `iam` 複製 aws 6.69.0，使用者跑 `init -backend=false` 與 `providers lock -platform=darwin_arm64 -platform=linux_amd64` 加上 helm 3.3.0。

### C6：application 與範例 chart

- `application` 不建資源，發布 design §8.1 的 `application` 新 key。舊的 `cluster_name`、`*_service_name`、`*_log_group_name` **先保留**，因為 C7 之前 `postdeploy` 還在讀。
- 範例 chart 放在 `templates/example3/deploy/charts/app/`：Deployment、ServiceAccount（名稱讀 SSM）、Service、TargetGroupBinding（`elbv2.k8s.aws/v1beta1`，不帶 `networking`）、ScaledObject 與 TriggerAuthentication（design §9 的指標契約）、`app` 的 NetworkPolicy（放行 ALB、CoreDNS 的 UDP 與 TCP 53、DB proxy、Redis、AWS API）。
- `bridge` 加入新 key，舊 key 也先保留。

驗收：同 C3；`helm lint`、`helm template` 通過；新 key 的 JSON 欄位有 `jsondecode` 斷言。

C6 的結果：

- `application`：ECS 照舊（design C6-1），多發布 9 個部署合約 key（C6-2）；`api_environment_json`、`worker_environment_json` 斷言等於 ECS task 的環境變數，而且不含 secret 值。`bridge` 不用改：`application` 讀的樹 B key 沒有變。
- `templates/example3/deploy/`：`values-from-ssm.sh` 與 `charts/app`（C6-3、C6-4、C6-5）。chart 的 ScaledObject 照 design §9；`aws-cloudwatch` 的參數名稱對照 KEDA 2.21 文件。
- 測試：TDD，先寫 `application.tftest.hcl` 的新 run 與 `check-deploy-values.sh` 看到失敗再實作。突變 12 個：ServiceAccount 改用 release 名稱、TargetGroupBinding 帶 `networking`、Deployment 寫死 `replicas`、DNS 少 TCP、RequestCountPerTarget 改 AverageValue、拿掉 namespace 檢查、worker 收 ingress、多認一個合約版本、不檢查缺 key、讀沒發布的 key、DNS 位址錯、少 keepalive sysctl。第一輪有 3 個沒被抓到（子字串比對、沒斷言 `metricType: Value`、缺 key 由 jq 先失敗），補了斷言後都抓到。

### C7：loadbalancer、postdeploy、拿掉 ECS

- `loadbalancer`：`canary` 預設 `null`。測試涵蓋 design §6.1 列的四種情況。
- `postdeploy`：`eks-workload-alarms`；`stream-alarms.tf` 照搬；log 告警改看 Container Insights 的 application log group。
- 所有 consumer 都切到新 key 之後，拿掉 `iam` 的 ECS role 與權限、`bridge` 與 `application` 的舊 key。

驗收：同 C3；`grep` 確認 example3 沒有 `ecs-*` module、ECS 的 SSM key 與 `ecs-tasks.amazonaws.com`（README 的差異說明除外）。

C7 的結果（設計見 design C7-1 到 C7-6）：

- `loadbalancer`：`canary` 物件與 `canary.tf`（`iam-role`、`lambda-function`、`lb-traffic-breaker`）。測試涵蓋 §6.1 的四種情況：關閉時零個 canary 資源；開啟時第二個 target group、加權 rule、breaker 接線與 Lambda 權限只到三條 rule；`weight > 0` 沒有 breaker 被擋下；SSM 只在開啟時發布 `api_canary_target_group_arn`。
- `containerimage`：tfvars 加 `traffic-breaker`。`postdeploy`：`eks-workload-alarms`，log 告警改看 `/aws/containerinsights/<cluster>/application`。
- 拿掉 ECS：`iam` 三個 role、`application` 的 ECS module 與變數、`bridge` 三個 key、README 的樹 B 表（33 個 key）。network 的 SG 描述拿掉 ECS 字樣（SG 會重建，範本還沒有環境 apply 過）。
- 測試先後：iam、containerimage、loadbalancer、腳本先看到失敗再實作；application 與 postdeploy 改測試後被合約檢查擋住，沒有單獨看到 RED，改以突變補驗。14 個突變：pod role 加回 ECS Exec、application 加回舊 key、container 名稱、namespace、log group、filter 欄位、忽略權重、breaker 能改 listener、拿掉 weight 的檢查、canary key 永遠發布、breaker 看 stable target group、canary 自建 ServiceAccount、canary 用 stable 的維度、拿掉 breaker repository，都被抓到。
- code review 後補上：canary target group 名稱超過 32 字元時由 `var.canary` 提早擋下；`canary.tftest.hcl` 換掉了 alb 的輸出，所以另外用真的 alb module 確認 breaker 讀的 key；`values-from-ssm.sh --canary` 檢查 ARN 格式。

### C8：收尾

- README：apply 順序、design §7 的執行環境與前提、SSM 合約表（含 Type 與 JSON 欄位）、跟 example2 的差異、design §6.1 的 canary runbook、design §11 的未確認事項。
- 保密：對 example3 全目錄做來源字串反向比對。
- 全量 `scripts/validate.sh`。
- 驗證紀錄分兩張表：
  - **靜態驗證通過**：`validate.sh`、`check-ssm-contract.sh`、`helm lint`、`helm template`、保密比對。
  - **雲端整合待驗證**（要真實帳號，這個里程碑不做）：node 加入叢集、DNS（實際 resolver、UDP 與 TCP 53）、Pod Identity 取得憑證與 secret、TargetGroupBinding 註冊 target 以及刪除後保留 target group、KEDA 依三個指標擴縮與縮容、CloudWatch 採集涵蓋 `app` 與 `system` node、每條告警能觸發、no-NAT 時的 endpoint 路徑、canary 權重與斷路器的完整流程。

驗收：全量通過；使用者審過 README 與兩張驗證表。

C8 的結果：

- `templates/example3/infra/README.md` 整份改寫：跟 example2 的差異、執行環境與前提（design §7）、EKS 合約與部署合約（含 Type 與 JSON 欄位）、CI 部署流程、canary 與斷路器的操作步驟（design §6.1）、IP 預算（K2）、destroy 前要先處理的事、已知限制（design §11 加上沿用 example2 的項目）、兩張驗證表。
- 保密：example3 全目錄跑 9 組去機密 pattern，命中的只有佔位 id 與 Kubernetes 的 API group；來源字串反向比對，example3 比 example2 多出來的只有 `aws:SourceAccount`、`RequestCountPerTarget`、`TargetGroup` 這類 AWS 公開名稱。
- 驗證紀錄：靜態驗證通過與雲端整合待驗證兩張表放在 README 的〈驗證〉，不另外建檔，避免兩份不同步。
