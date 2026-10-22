# infra-platform v4 設計文件：example3（example2 的 EKS 版）

> 狀態：設計草案，第二版。§3.1 是使用者拍板的決策；§3.2 的 K1–K8 與 §9 的 W1–W4 已經使用者審閱並定案（2026-10-22）。審過才進實作，步驟見 [`implement-process.md`](./implement-process.md)。
> 範圍：把 `templates/example2` 複製成 `templates/example3`，在 example3 裡把 ECS 換成 EKS。example2 維持 ECS，一行都不改。這次只寫設計，不寫程式碼。
> 文中路徑除非特別註明，都是 repo 內相對路徑。「v3 §x」指 [`../v3/design-docs.md`](../v3/design-docs.md)。example2 的路徑都在 `templates/example2/infra/terraform/` 底下，下文省略這段前綴。
> AWS 與 KEDA 的行為是 2026-10-22 查證的結果，來源列在 §12。標「未確認」的要在實作或真實環境驗證。

## 1. 結論

example3 用 EKS Auto Mode 跑 api 與 worker，其他部分沿用 example2：

- **節點**：Auto Mode，完全不用內建 NodePool。叢集建立時 `nodePools` 與 `nodeRoleArn` 都留空，再由 Terraform 建 node role 的 EC2 access entry，由 `eks-addons` 建自訂的 NodeClass／NodePool。
- **pod 網路**：NodeClass 層級的 Pod SG（沿用 example2 的 `app` SG 規則）、Kubernetes NetworkPolicy（預設 `DefaultDeny`）、node 與 pod 分開的 SG。Auto Mode 不支援傳統的 SecurityGroupPolicy／`ENABLE_POD_ENI`。pod 出 VPC 的限制主要靠 NetworkPolicy（§2 第 2 點、K1）。
- **ALB**：模式 T（v3 D9）。Terraform 擁有 ALB、listener、target group；pod 透過 AWS Load Balancer Controller 的 `elbv2.k8s.aws/v1beta1` TargetGroupBinding 註冊進 target group。不用 Auto Mode 原生的 TargetGroupBinding，因為它的生命週期會刪掉 target group，跟「Terraform 擁有 target group」衝突。
- **部署**：api、worker 由 CI 用 Helm 部署。Terraform 準備好叢集、namespace、Pod Identity、target group，再把部署需要的值寫進 SSM；CI 讀 SSM 後部署。repo 附一份範例 chart。
- **擴縮**：KEDA，延續 example2 的擴縮目的（worker 看 stream backlog，api 看 CPU、每個 target 的請求數與連線數），指標契約見 §8。不承諾跟 ECS 的 step scaling 行為相同。
- **告警**：新 module `eks-workload-alarms`，直接建 `aws_cloudwatch_metric_alarm`，取代 `ecs-service-alarms`（§10）。worker 的 backlog 與 consumer 告警沿用 example2 的 `postdeploy/stream-alarms.tf`。
- **API endpoint**：只有 private，沒有開 public 的選項。Helm 要從 VPC 或可連通的網路執行（§7）。

要先改或新增的 module（§5）：`eks-cluster` 0.2.0、`eks-addons` 0.2.0、`eks-iam-policies` 0.2.0、`iam-role` 0.4.0、新 module `eks-workload-alarms` 0.1.0。這些都要先發版、HCP 登記好，範本才能開始做。

## 2. 查證時發現、會影響設計的事

1. **Pod SG 是 NodeClass 層級**。`podSubnetSelectorTerms` 與 `podSecurityGroupSelectorTerms` 必須一起設定；同一個 NodeClass 上所有 pod 共用同一組 Pod SG。要讓兩種工作負載用不同的 SG，就要兩組 NodeClass／NodePool，再用 taint、toleration 或 nodeSelector 分開。example2 的 api 與 worker 共用同一個 `app` SG（`network/security-groups.tf:6`），所以 example3 一組 `app` NodeClass 就夠。
2. **Pod SG 只管 VPC 內的流量**。出 VPC 的流量預設經過 SNAT（`snatPolicy: Random`），換成 node 的 IP，套用的是 node 的 SG（`securityGroupSelectorTerms`）。
3. **Auto Mode 不支援 Security Groups for Pods（SGPP）**，也就是 VPC CNI 的 SecurityGroupPolicy 與 `ENABLE_POD_ENI`。要用 NodeClass 的 `podSecurityGroupSelectorTerms`。
4. **NetworkPolicy 要明確啟用**：在 `kube-system` 建名為 `amazon-vpc-cni` 的 ConfigMap，`enable-network-policy-controller: "true"`。NodeClass 另外設 `networkPolicy`（`DefaultAllow` 或 `DefaultDeny`）與 `networkPolicyEventLogs`。
5. **完全不用內建 NodePool 時，node access entry 要自己建**。AWS 的流程是建叢集時 `nodePools`、`nodeRoleArn` 都留空，再建自訂 NodeClass、node role 的 EC2 類型 access entry（關聯 `AmazonEKSAutoNodePolicy`）與 NodePool。EKS 只在建立時指定了 node role 才會自動建 access entry，所以 example3 由 Terraform 明確建立。`eks-cluster` 0.1.0 不支援這個組合（§5）。
6. **Auto Mode 原生的 TargetGroupBinding 會在生命週期裡刪掉 target group**（使用者查證），所以模式 T 改用 AWS Load Balancer Controller 的 `elbv2.k8s.aws/v1beta1` TargetGroupBinding。`eks-cluster` 開 Auto Mode 時一定會開 elastic load balancing 能力（`modules/eks-cluster/variables.tf:245`），兩個 controller 會並存，範圍要分清楚（§11 第 2 點）。
7. **加權 target group 不會自動 failover**。ALB 不會因為某個加權 target group 是空的或不健康，就把流量轉給另一組（v3 §2）。所以 canary 的權重控制要有明確的規則（§6.1）。
8. **private endpoint 只限制「要呼叫 Kubernetes API」的操作**。Helm、kubernetes provider 要從 VPC 或可連通的網路執行；只呼叫 AWS API 的 Terraform（建 EKS、IAM、access entry、Pod Identity association）不受影響。執行 Helm 的身分還要有對應的 access entry 與 RBAC。
9. **`eks-addons` 0.1.0 只有 Karpenter 用的預設 NodePool**（`modules/eks-addons/charts/karpenter-defaults`），沒有 Auto Mode 的 NodeClass（`eks.amazonaws.com/v1`）與 NodePool。
10. **repo 目前的封裝與 vendoring 策略是「一個 module 一個獨立單位」**：HCP 依 `modules/<name>` 目錄各自發佈，`scripts/vendor-modules.sh` 一次複製一個 module，repo 裡沒有 module 引用另一個 module。Terraform 本身支援 package 內的 module 引用，但要用的話這兩條路徑都得重新設計，所以 `eks-workload-alarms` 直接建資源（W1）。
11. **Container Insights（enhanced observability）的 EKS 指標**：Deployment 的副本數是 `replicas_desired`、`replicas_ready`（維度 `ClusterName` 或 `PodName`、`Namespace`、`ClusterName`）；pod 層級有 `pod_status_pending`、`pod_container_status_waiting_reason_crash_loop_back_off`、`pod_container_status_terminated_reason_oom_killed`、`pod_number_of_container_restarts` 等，namespace 是 `ContainerInsights`。
12. **KEDA 的 `aws-cloudwatch` scaler** 需要 `cloudwatch:GetMetricData`，參數有 `metricStat`、`metricStatPeriod`、`metricCollectionTime`、`targetMetricValue`、`minMetricValue`（沒資料時回傳的值，預設 0）等。

## 3. 決策

### 3.1 使用者拍板（2026-10-22）

| # | 主題 | 決定 |
|---|---|---|
| E1 | 範本 | 複製 example2 成 `templates/example3`，在 example3 把 ECS 換成 EKS；example2 不動 |
| E2 | 節點 | EKS Auto Mode |
| E3 | pod 網路 | 自訂 NodeClass／NodePool、Pod 專用 SG（NodeClass 層級）、NetworkPolicy。Pod subnet 與 Pod SG 欄位一起設定，NetworkPolicy controller 明確啟用 |
| E4 | ALB | 模式 T：Terraform 擁有 ALB 與 target group；另裝 AWS Load Balancer Controller，用 `elbv2.k8s.aws/v1beta1` TargetGroupBinding；不用 Auto Mode 原生 TGB（§2 第 6 點） |
| E5 | 斷路器 | `lb-traffic-breaker` 接上，預設關閉 |
| E6 | 擴縮 | KEDA |
| E7 | 部署 | CI 用 Helm 部署 api、worker；Terraform 發布 SSM 合約；附範例 chart |
| E8 | 告警 | 新 module `eks-workload-alarms` |
| E9 | pod 的 AWS 權限 | Pod Identity（v3 D7） |
| E10 | API endpoint | 只有 private |
| E11 | stack 順序 | `eks-cluster`、`eks-addons` 放在 `bridge` 之後。這不是永久限制：叢集另外發布版本化的 EKS 合約給其他專案用（§8.1） |
| E12 | 其他 stack | `agent`、`operation`、`bridge` 照搬，只改 SSM 合約的 key；改完逐一驗證 producer 與 consumer 的合約相容（§8.1） |
| E13 | helm lock hash | 使用者在自己的終端機跑 `terraform providers lock` |
| E14 | 擁有者 | 每個資源實例、以及資源上每個受管理的欄位，都有明確的擁有者（§4） |

### 3.2 審閱後定案的判斷（K1–K8）

- **K1 node SG 另建**：`network` 新增一個 `node` SG，NodeClass 的 `securityGroupSelectorTerms` 選 EKS 建的 cluster SG 加上這個 `node` SG。`app`↔`node` 的規則都在 `network` 定義，避開「`network` 要讀 `eks-cluster` 建的 cluster SG」的跨 stack 循環。**限制**：cluster SG 的 egress 是全開的，node 同時掛著它，新增的 `node` SG 不會把對外流量收窄。pod 出 VPC 的限制主要靠 NetworkPolicy（K5）；VPC 內的流量才由 Pod SG（`app`）收窄。
- **K2 pod 與 node 共用 `app` subnet（目標方案）**：node 與 pod 都選 `app` subnet（`network/vpc.tf:6`），靠 tag 區分。是否夠用要算 IP 預算，不能直接下結論：每個 AZ 需要的 IP ≈（最多 node 數 × 擴縮與替換時並存的倍數）×（1 個 node IP ＋ 每台 node 的 pod prefix 數 × 16）。Auto Mode 預設用 /28 prefix，每台 node 至少保留 16 個 pod IP；drift 替換、consolidation 時新舊 node 會同時存在。C3 依 tfvars 的上限算一次，寫進 README。同一個 subnet 給 node 與 pod 用的行為列為整合驗證；不行就在 `vpc_subnets` 加一個 `pod` tier。
- **K3 `app` 與 `system` 分池**：api、worker 用 `app` NodeClass／NodePool（掛 Pod SG）；LB Controller、KEDA 的 Deployment 放 `system` NodePool（有 taint，只有帶 toleration 的系統元件會排上去）。**例外**：CloudWatch agent 與 Fluent Bit 是 DaemonSet，必須涵蓋 `app` node，所以要帶能容忍兩個 pool 的 toleration。
- **K4 共用 node role，access entry 由 Terraform 建**：`app`、`system` 兩個 NodeClass 用同一個 node role。叢集建立時不指定 node role（§2 第 5 點），由 `eks-cluster` 建這個 role 的 EC2 類型 access entry，關聯 `AmazonEKSAutoNodePolicy`。
- **K5 NetworkPolicy 預設 `DefaultDeny`**：`app` 與 `system` 都要有對應的放行規則。`system` 的規則由平台 bootstrap（`eks-addons`）管：Kubernetes API、DNS、webhook（LB Controller、KEDA）、metrics、AWS API（VPC endpoint 或 NAT）。`app` 的規則在 chart 裡（§4）。DNS 的驗收要確認實際使用的 resolver（Auto Mode 的 CoreDNS 跑在每台 node 本機，IP 是 service CIDR 的 `.10`），UDP 與 TCP 53 都要涵蓋。
- **K6 範本不建 runner**：文件統一寫「VPC 或可連通的網路」，前提列在 §7。
- **K7 KEDA 的 policy**：`eks-iam-policies` 輸出 policy，`iam` stack 建 role，`eks-cluster` 的 Pod Identity association 連到 KEDA operator 的 ServiceAccount。
- **K8 斷路器預設零資源**：「零資源」指沒有額外的 canary target group、加權 rule、breaker 與相關告警。啟用的完整路徑見 §6.1，測試不能只驗證 Terraform 建得出第二個 target group。

## 4. 擁有者

原則：每個資源實例、以及資源上每個受管理的欄位，都只有一個擁有者。兩個 module、或 Terraform 與執行期的程式同時改同一個欄位，是這次最要避免的事；真的無法避免的（canary 權重），要寫明控制權怎麼交接。

| 擁有者 | 管理範圍 | 怎麼執行 |
|---|---|---|
| `eks-cluster`（module 與同名 stack） | EKS 叢集、access entry（node role 的 EC2 entry、叢集管理者、`eks-addons` 的 apply 身分、CI 部署身分）、Pod Identity association、EKS 合約的輸出 | 只呼叫 AWS API，任何地方都能跑 |
| `iam` stack | cluster role、node role、api／worker 的 Pod Identity role、LB Controller、KEDA、CloudWatch 採集元件的 role | 只呼叫 AWS API |
| `eks-addons`（module 與同名 stack，平台 bootstrap） | NodeClass／NodePool、namespace、NetworkPolicy controller 啟用、`system` 的 NetworkPolicy、KEDA、AWS Load Balancer Controller、CloudWatch 採集 | Helm，要在 VPC 或可連通的網路 |
| CI 與範例 chart | api、worker 的 Deployment、ServiceAccount、Service、TargetGroupBinding、KEDA ScaledObject 與 TriggerAuthentication、`app` 的 NetworkPolicy | Helm，要在 VPC 或可連通的網路 |
| `loadbalancer` stack | ALB、listener、rule、target group、WAF、access log；canary 開啟時的第二個 target group 與加權 rule、`lb-traffic-breaker` | 只呼叫 AWS API |
| `lb-traffic-breaker` 的 Lambda（執行期） | 只有一個欄位：加權 rule 的權重，在 alarm 觸發時改成 stable 100%、canary 0 | 執行期，由 alarm 呼叫 |
| `eks-workload-alarms`（`postdeploy` stack 呼叫） | api、worker 的工作負載告警 | 只呼叫 AWS API |

幾條要寫進 chart 與 README 的界線：

- TargetGroupBinding 不能帶 `networking` 區塊，不然 LB Controller 會改 Terraform 擁有的 SG 規則。
- chart 不建 Ingress、`type: LoadBalancer` 的 Service；ALB 只有 Terraform 建。
- ServiceAccount 名稱與 namespace 由 Terraform 決定、寫進 SSM，chart 照讀，不能自己取名，否則 Pod Identity association 對不上。
- 加權 rule 的權重：Terraform 擁有「設定值」，breaker 擁有「觸發後的執行期覆寫」。交接規則見 §6.1。

## 5. Module 變更

| module | 版本 | 內容 |
|---|---|---|
| `eks-cluster` | 0.1.0 → 0.2.0 | `auto_mode.node_role_arn` 改成選填，`node_pools = []` 時可以留空；`access_entries` 支援 `EC2` 類型並能關聯 `AmazonEKSAutoNodePolicy`（目前只接受 `STANDARD`、`EC2_LINUX` 等，而且只有 `STANDARD` 能關聯 policy，`variables.tf:338-385`）；輸出 cluster SG 與 service CIDR |
| `eks-addons` | 0.1.0 → 0.2.0 | Auto Mode 的 NodeClass／NodePool（本地 chart，`eks.amazonaws.com/v1`，含 Pod subnet／Pod SG、`networkPolicy`、`networkPolicyEventLogs`）；`amazon-vpc-cni` ConfigMap 啟用 NetworkPolicy controller；`system` 的 NetworkPolicy；KEDA；CloudWatch 採集（W3） |
| `eks-iam-policies` | 0.1.0 → 0.2.0 | 輸出 KEDA 讀 CloudWatch 指標的 policy（`cloudwatch:GetMetricData`，K7） |
| `iam-role` | 0.3.0 → 0.4.0 | managed policy 白名單加入 `CloudWatchAgentServerPolicy`（W2） |
| `eks-workload-alarms` | 新，0.1.0 | api、worker 的工作負載告警，直接建 `aws_cloudwatch_metric_alarm`，沿用既有告警的寫法與測試慣例，不依賴其他 module（W1、§10） |
| `vpc` | 0.2.0（已發） | subnet tag，給 NodeClass 的 selector 用；example3 從 0.1.0 升上來 |

## 6. example3 的 stack

ORDER（C5 完成後）：

```
containerimage foundation network database iam bridge eks-cluster eks-addons loadbalancer agent application operation postdeploy
```

| stack | 跟 example2 比 |
|---|---|
| `containerimage`、`foundation`、`database`、`agent`、`operation` | 照搬（E12）；`containerimage` 只改描述文字 |
| `network` | `vpc` 升 0.2.0、`app` subnet 加 NodeClass 用的 tag；新增 `node` SG（K1）；`app` SG 加 node↔pod 需要的規則（kubelet 探測、DNS，**未實測**）；`nat_mode = "none"` 時加 EKS 需要的 interface endpoint（v3 §5 第 1 步的清單，再加 KEDA 讀指標用的 `monitoring`，**完整性未確認**） |
| `iam` | 拿掉 `ecs_execution`、`api_task`、`worker_task` 與 ECS Exec 權限（`iam/roles.tf:6-17`、`iam/policies.tf`）；新增 §4 列的 role |
| `bridge` | 轉發的 key 從三個 ECS role 換成 `api_pod_role_arn`、`worker_pod_role_arn` |
| `eks-cluster`（新） | 叢集（private endpoint、Auto Mode、`node_pools = []`、不指定 node role）、node role 的 EC2 access entry、其他 access entry、Pod Identity association、secrets 加密的 KMS key |
| `eks-addons`（新） | 呼叫 `eks-addons` 0.2.0；helm provider 由 SSM 讀到的 endpoint 與 CA 設定，用 `aws eks get-token` |
| `loadbalancer` | 不變的部分：ALB、WAF、origin-verify、access log、`api` target group（已經是 `ip` 類型，`loadbalancer/alb.tf:61-67`）；新增 `canary`（§6.1） |
| `application` | 從「建 ECS service」改成「發布部署合約」：不建資源，只把 chart 需要的值寫進 SSM（§8.1） |
| `postdeploy` | `ecs-service-alarms` 換成 `eks-workload-alarms`；`stream-alarms.tf` 照搬；log 告警改看 Container Insights 的 application log group |

### 6.1 canary 與斷路器

`loadbalancer` 加一個 `canary` 物件，預設 `null`，這時不建任何 canary 相關資源。給了才建：

| 元件 | 內容 |
|---|---|
| 第二個 target group | `api_canary`，`ip` 類型，ARN 發布成 SSM `api_canary_target_group_arn` |
| 誰註冊進去 | CI 用同一份 chart 再部署一個 release（例如 `api-canary`，不同的 image tag），它的 TargetGroupBinding 指向 `api_canary_target_group_arn`。stable 的 release 只綁 `api` target group |
| 加權 rule | 原本的 api rule 改成加權 forward：`api` 與 `api_canary` |
| 權重 | `canary.weight`（0–100），由 tfvars 決定 |
| 斷路器 | `lb-traffic-breaker`：alarm 看 `api_canary` 的 5xx 錯誤率與健康主機數，觸發後 Lambda 把權重改成 stable 100、canary 0 |

權重的規則：

1. **什麼時候可以大於 0**：canary release 已經部署、`api_canary` 有健康的 target 之後。Terraform 看不到 target 健康狀態，所以這是 runbook 的步驟；validation 只擋「`weight > 0` 卻沒有開斷路器」。ALB 不會因為 canary 是空的或不健康就轉走流量（§2 第 7 點），權重先開、target 還沒註冊，那部分請求就會失敗。
2. **斷路器改了權重之後**：下一次 `terraform apply` 會把權重改回 tfvars 的值（v3 R1）。runbook：斷路器觸發後，先把 tfvars 的 `canary.weight` 改成 0 並 apply，確認後才處理 canary release；不加 `ignore_changes`（沿用 v3 的決策）。
3. **收尾**：canary 驗證完成後，把 stable release 換成新 image、`canary.weight` 改回 0，再移除 canary release；要完全拿掉 canary 資源時把 `canary` 設回 `null`。

測試要涵蓋：關閉時零個 canary 資源；開啟時第二個 target group、加權 rule、breaker 與 alarm 的接線；`weight > 0` 而沒有斷路器時被擋下；SSM 有發布 `api_canary_target_group_arn`。

## 7. 執行環境

| 操作 | 在哪裡執行 | 前提 |
|---|---|---|
| `eks-addons` stack 的 apply、CI 的 Helm 部署 | VPC 或可連通的網路（self-hosted runner、VPC 內的 CodeBuild、VPN、bastion） | 見下方清單 |
| 其他 stack（含 `eks-cluster`） | 任何能呼叫 AWS API 的地方 | 跟 example2 相同 |

VPC 或可連通的網路要滿足：

- **DNS**：能解析叢集的 private endpoint。在 VPC 內用 VPC 的 resolver；在 VPC 外要有 Route 53 Resolver inbound endpoint 或等效的轉發。
- **路由**：到 `app` subnet（控制平面 ENI 所在）的路由。
- **SG**：控制平面的 SG 允許來自 runner 的 443。runner 的來源（SG 或 CIDR）由 tfvars 給，`network` 建規則。
- **AWS 權限**：`eks:DescribeCluster`，以及產生 token 用的 STS 呼叫。
- **Kubernetes 授權**：`eks-cluster` 為 runner 的身分建 access entry。`eks-addons` 的 apply 身分要叢集範圍的權限；CI 的部署身分限 `app_namespace`。

範本不建 runner（K6），README 寫清楚上面的前提。

## 8. 合約

### 8.1 SSM

| stack | 拿掉 | 新增 |
|---|---|---|
| `iam` | `ecs_execution_role_arn`、`api_task_role_arn`、`worker_task_role_arn` | `eks_cluster_role_arn`、`eks_node_role_arn`、`api_pod_role_arn`、`worker_pod_role_arn`、`lb_controller_role_arn`、`keda_role_arn`、`cloudwatch_agent_role_arn` |
| `bridge`（tree B） | 三個 ECS role | `api_pod_role_arn`、`worker_pod_role_arn` |
| `eks-cluster` | — | `contract_version`、`cluster_name`、`cluster_endpoint`、`cluster_ca_data`、`cluster_sg_id`、`service_cidr`、`app_namespace`、`api_service_account`、`worker_service_account` |
| `application` | `cluster_name`、`*_service_name`、`*_log_group_name`（C7 才拿掉，見 implement-process C6） | `api_environment_json`、`worker_environment_json`、`api_target_group_arn`（轉發，讓 CI 只讀一個前綴）、image repository URL、副本數上下限、`stream_length_cap` |

交付語意：

- **Type 與內容格式分開**。SSM 參數的 Type 只有 `String`、`StringList`、`SecureString`；JSON 是 `String` 裡的內容格式。合約檢查分兩層：`check-ssm-contract.sh` 驗 key 與 Type（它已經比對 String 與 StringList）；JSON 的 schema（有哪些欄位、型別）由 producer stack 的 `terraform test` 以 `jsondecode` 斷言，consumer（chart）的範例 values 也照同一份欄位清單。example3 不用 `SecureString`，secret 都在 Secrets Manager。
- **版本化的 EKS 合約**。`eks-cluster` 的 key 帶 `contract_version`，欄位有不相容的變動才升版。其他專案要共用這個叢集時讀這組 key，不必經過 `bridge`；E11 的順序只是 example3 自己的 apply 順序。
- **只改 key 也要驗證相容**（E12）。每個 Phase 結束跑 `check-ssm-contract.sh`，並逐一比對 consumer 讀的 key、Type 與 JSON 欄位跟 producer 發布的一致。

### 8.2 secret

環境變數只放 secret 的 ARN，不放 secret 值，跟 example2 一樣（`application/environment.tf:29` 的註解：task 用自己的 role 取值）。example3 沿用這個流程：

- **誰取值**：應用程式用 AWS SDK，以 Pod Identity 拿到的 role 呼叫 Secrets Manager。Helm 不會解析 ARN，chart 只把 ARN 當成一般環境變數傳進去。
- **要驗證的**：應用程式使用的 SDK 版本支援 Pod Identity 的 container credentials provider（`AWS_CONTAINER_CREDENTIALS_FULL_URI`）；api／worker 的 Pod Identity role 有對應 secret 的 `secretsmanager:GetSecretValue`（沿用 example2 task role 的權限範圍）。
- `tcp_keepalive_*` 從 ECS 的 `system_controls` 改成 pod 的 `securityContext.sysctls`，由 chart 設定。這三個是 namespaced sysctl，Kubernetes 1.29 起屬於安全 sysctl，**未實測**。

## 9. 擴縮（KEDA）

延續 example2 的擴縮目的，但不承諾行為跟 ECS 的 step scaling 相同。每個 ScaledObject 的指標契約：

| 工作負載 | 觸發 | metric、dimensions | 統計 | 目標 | metricType |
|---|---|---|---|---|---|
| worker | `aws-cloudwatch` | `<Project>/<env>` 的 `StreamBacklogMax`，`Env=<env>`（跟 example2 同一個指標） | `Maximum`，`metricStatPeriod=60`，`metricCollectionTime=300` | 每個副本承擔 `stream_length_cap / 4` 的 backlog | `AverageValue` |
| api | CPU（HPA 內建的 resource metric） | — | — | 平均使用率 `api_cpu_target_percent`（預設 60） | `Utilization` |
| api | `aws-cloudwatch` | `AWS/ApplicationELB` 的 `RequestCountPerTarget`，`TargetGroup=<api TG suffix>`、`LoadBalancer=<alb suffix>` | `Sum`，`metricStatPeriod=60` | `api_requests_per_target`（預設 300） | `Value`（指標本身已經是每個 target 的值） |
| api | `aws-cloudwatch` | `AWS/ApplicationELB` 的 `ActiveConnectionCount`，`LoadBalancer=<alb suffix>` | `Sum`，`metricStatPeriod=60` | 每個副本 `api_streams_per_task_high`（預設 100） | `AverageValue` |

其他規則：

- **沒有資料時**：`minMetricValue=0`，也就是視為沒有負載，最多縮到 `minReplicaCount`。指標整個斷掉（reporter 停了）由 `postdeploy` 的 `no_consumers` 告警抓（`treat_missing_data = breaching`）。
- **縮容**：HPA 的 `behavior.scaleDown` 設穩定時間 900 秒、每 600 秒最多減 1 個副本，對應 example2「backlog 低於 cap 的 1/20、持續 15 分鐘才縮」的意圖。
- **副本上限**：`maxReplicaCount` 沿用 tfvars 的 `api_max_capacity`、`worker_max_capacity`。每個副本都會開 DB proxy 與 Redis 連線（`application/variables.tf:75`），上限要以「副本數 × 每個副本的連線數 ≤ DB proxy 可承受的連線數」決定，README 寫明檢查方式。
- **權限**：KEDA operator 用 Pod Identity（K7），ScaledObject 的 TriggerAuthentication 指定 operator 身分。KEDA 版本與 `metricType` 的實際行為在 C1 對照文件確認。

## 10. 告警（`eks-workload-alarms`）

每條規則都寫明 metric、dimensions、統計、觀察時間與 missing-data 行為。不用固定的「Running pod 下限」，因為擴縮後副本數會變。

| 規則 | metric（namespace `ContainerInsights`，除非註明） | dimensions | 統計與觀察時間 | 條件 | missing data |
|---|---|---|---|---|---|
| Ready 長時間低於期望 | metric math：`replicas_desired - replicas_ready` | `ClusterName`、`Namespace`、`PodName`（工作負載名稱，**未確認**） | 兩個都用 `Average`，period 60，10 個 period 中 10 個 | 差距 > 0 | `breaching`（採集停止也該知道） |
| CrashLoop | `pod_container_status_waiting_reason_crash_loop_back_off` | `ClusterName`、`Namespace`、`Service`（api）；worker 沒有 Service，用 `PodName` 那組 | `Maximum`，period 60，5 個 period 中 3 個 | > 0 | `notBreaching` |
| 近期重啟 | `pod_number_of_container_restarts` | `PodName`、`Namespace`、`ClusterName` | `Sum`，period 300，1 個 period；如果這個指標是累計值，改用 metric math `DIFF` | 增量 > `restart_threshold` | `notBreaching` |
| 持續 Pending | `pod_status_pending` | 同 CrashLoop | `Maximum`，period 60，10 個 period 中 10 個 | ≥ 1 | `notBreaching` |
| OOM | `pod_container_status_terminated_reason_oom_killed` | `ContainerName`、`PodName`、`Namespace`、`ClusterName` | `Sum`，period 300，1 個 period | > 0 | `notBreaching` |
| api：target 5xx、p95 延遲、健康主機數 | `AWS/ApplicationELB` 的 `HTTPCode_Target_5XX_Count`、`TargetResponseTime`、`HealthyHostCount` | `TargetGroup`、`LoadBalancer` | 照 `ecs-service-alarms` 既有的設定 | 照既有 | 照既有 |
| worker：backlog 與 consumer | — | — | 沿用 `postdeploy/stream-alarms.tf` 的 `backlog_high`、`no_consumers`，不放進新 module | — | — |

`pod_number_of_container_restarts` 是每個 period 的增量還是累計值、`PodName` 維度在 Deployment 上的實際值，C1 對照 AWS 文件或在真實叢集確認後再定。

## 11. 風險與 mock 驗不到的事

1. **node 與 pod 選同一個 subnet 行不行，以及 IP 預算**（K2）。
2. **兩個 TargetGroupBinding controller 並存**：Auto Mode 的 load balancing 能力關不掉，LB Controller 又另外裝。要確認兩者不會搶同一個資源、LB Controller 的 webhook 不影響 Auto Mode，以及刪除 TargetGroupBinding 時 LB Controller 只解除註冊、保留 Terraform 的 target group。**未確認**。
3. **`app` SG 要補的規則**：kubelet 探測 pod、pod 查 node 上的 CoreDNS，都是 VPC 內的流量，會經過 Pod SG。少了會導致探測失敗、DNS 失敗。
4. **`DefaultDeny` 下的系統元件**：bootstrap 的放行規則漏一條，LB Controller 或 KEDA 的 webhook、metrics 就會失效（K5）。
5. **Pod Identity association 早於 namespace 與 ServiceAccount 存在**（v3 §6 已列）。
6. **LB Controller 的官方 policy 能不能對 Terraform 建的 target group 做 `RegisterTargets`**。
7. **helm provider 用 SSM 讀到的值設定**，mock 測試與真實 plan 是否都能過。
8. **no-NAT 時的 interface endpoint 是否齊全**（Auto Mode、KEDA、CloudWatch 採集都會打 AWS API）。
9. **KEDA 依 CloudWatch 指標擴縮，對長連線（SSE）的實際效果**（§9）。
10. **Container Insights 包了一層之後，`$.event` 這類 log filter 還能不能比對**（`postdeploy/log-alarms.tf`）。
11. **Kubernetes 版本**：placeholder 選目前仍在標準支援的版本（1.35 以上），C4 再查。
12. **保密**：example3 是從 example2 複製，只能帶 example2 已有的字串；每個 phase 都做來源字串的反向比對（[`../v2/integration-playbook.md`](../v2/integration-playbook.md)）。

## 12. 來源

- Create a Node Class for Amazon EKS（含〈Separate subnets and security groups for Pods〉〈Create node class access entry〉）：<https://docs.aws.amazon.com/eks/latest/userguide/create-node-class.html>
- Use Network Policies with EKS Auto Mode：<https://docs.aws.amazon.com/eks/latest/userguide/auto-net-pol.html>
- Container Insights with enhanced observability 的 EKS 指標：<https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-enhanced-EKS.html>
- KEDA `aws-cloudwatch` scaler：<https://keda.sh/docs/2.18/scalers/aws-cloudwatch/>
- 使用者 2026-10-22 查證：Auto Mode 原生 TargetGroupBinding 的生命週期、不用內建 NodePool 的建立流程、private endpoint 的影響範圍、加權 target group 不會自動 failover、SSM 參數的 Type（docs.aws.amazon.com）
- v3 的 EKS 決策：[`../v3/design-docs.md`](../v3/design-docs.md)
- 範本整合流程與保密規則：[`../v2/integration-playbook.md`](../v2/integration-playbook.md)

## 附錄：W1–W4 的決定（2026-10-22）

| # | 決定 | 文件裡的位置 |
|---|---|---|
| W1 | `eks-workload-alarms` 直接建 `aws_cloudwatch_metric_alarm`，沿用既有告警的寫法與測試慣例，不新增 module 相依。理由是 repo 目前的封裝與 vendoring 策略（§2 第 10 點） | §5、§10 |
| W2 | `iam-role` 白名單加入 `CloudWatchAgentServerPolicy`。權限給採集元件的 ServiceAccount；CloudWatch agent 與 Fluent Bit 各自用哪個 ServiceAccount，C1 確認後分別建 Pod Identity association | §5、implement-process C1 |
| W3 | `eks-addons` 用 Helm 裝 `amazon-cloudwatch-observability`。固定 chart 版本；採集模式是 Container Insights（enhanced observability）的 metrics 加 Fluent Bit 的 logs；Application Signals 預設關閉 | §5、implement-process C1、C5 |
| W4 | NetworkPolicy 預設 `DefaultDeny`；`app` 與 `system` 都要有放行規則，`system` 的由平台 bootstrap 管 | K5、§4 |
