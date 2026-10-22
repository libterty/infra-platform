# infra-platform v4 設計文件：example3（example2 的 EKS 版）

> 狀態：設計草案，等使用者審閱。§3.1 是使用者拍板的決策，§3.2 是我的判斷、使用者還沒表示意見，§9 是還沒決定的事。審過才進實作，步驟見 [`implement-process.md`](./implement-process.md)。
> 範圍：把 `templates/example2` 複製成 `templates/example3`，在 example3 裡把 ECS 換成 EKS。example2 維持 ECS，一行都不改。這次只寫設計，不寫程式碼。
> 文中路徑除非特別註明，都是 repo 內相對路徑。「v3 §x」指 [`../v3/design-docs.md`](../v3/design-docs.md)。example2 的路徑都在 `templates/example2/infra/terraform/` 底下，下文省略這段前綴。
> AWS 行為是 2026-10-22 查證的結果，來源列在 §11。標「未確認」的要在實作或真實環境驗證。

## 1. 結論

example3 用 EKS Auto Mode 跑 api 與 worker，其他部分沿用 example2：

- **節點**：Auto Mode，不用 managed node group、Karpenter、Fargate。不用內建的 NodePool，改用自訂的 NodeClass／NodePool，才能讓 pod 走自己的 subnet 與 security group。
- **pod 網路**：三層一起用。NodeClass 層級的 Pod SG（沿用 example2 的 `app` SG 規則）、Kubernetes NetworkPolicy、node 與 pod 分開的 SG。Auto Mode 不支援傳統的 SecurityGroupPolicy／`ENABLE_POD_ENI`。
- **ALB**：模式 T（v3 D9）。Terraform 擁有 ALB、listener、target group；pod 透過 AWS Load Balancer Controller 的 `elbv2.k8s.aws/v1beta1` TargetGroupBinding 註冊進 target group。不用 Auto Mode 原生的 TargetGroupBinding，因為它的生命週期會刪掉 target group，跟「Terraform 擁有 target group」衝突。
- **部署**：api、worker 由 CI 用 Helm 部署。Terraform 準備好叢集、namespace、Pod Identity、target group，再把部署需要的值寫進 SSM；CI 讀 SSM 後部署。repo 附一份範例 chart。
- **擴縮**：KEDA，依 CloudWatch 指標（worker 的 stream backlog、api 的 ALB 請求數）擴縮，行為最接近 example2。
- **告警**：新的 `eks-workload-alarms` module 取代 `ecs-service-alarms`。
- **API endpoint**：只有 private，沒有開 public 的選項。

要先改或新增的 module（§5）：`eks-addons` 0.2.0、`eks-iam-policies` 0.2.0、新 module `eks-workload-alarms` 0.1.0，可能還有 `iam-role` 的白名單與 `eks-cluster` 的小改動（§5 標明哪些要先查證）。這些都要先發版、HCP 登記好，範本才能開始做。

## 2. 查證時發現、會影響設計的事

1. **Pod SG 是 NodeClass 層級**。`podSubnetSelectorTerms` 與 `podSecurityGroupSelectorTerms` 必須一起設定；同一個 NodeClass 上所有 pod 共用同一組 Pod SG。要讓兩種工作負載用不同的 SG，就要兩組 NodeClass／NodePool，再用 taint、toleration 或 nodeSelector 分開。example2 的 api 與 worker 共用同一個 `app` SG（`network/security-groups.tf:6`），所以 example3 一組 `app` NodeClass 就夠。
2. **Pod SG 只管 VPC 內的流量**。出 VPC 的流量預設經過 SNAT，換成 node 的 IP，套用的是 node 的 SG（`securityGroupSelectorTerms`）。所以 pod 對外的限制要靠 node SG 與 NetworkPolicy，不是 Pod SG。
3. **Auto Mode 不支援 Security Groups for Pods（SGPP）**，也就是 VPC CNI 的 SecurityGroupPolicy 與 `ENABLE_POD_ENI`。要用 NodeClass 的 `podSecurityGroupSelectorTerms`。
4. **NetworkPolicy 要明確啟用**：在 `kube-system` 建名為 `amazon-vpc-cni` 的 ConfigMap，`enable-network-policy-controller: "true"`。NodeClass 另外可以設 `networkPolicy`（`DefaultAllow` 或 `DefaultDeny`）與 `networkPolicyEventLogs`。
5. **自訂 NodeClass 的 node role 要有 EC2 類型的 access entry**，並關聯 `AmazonEKSAutoNodePolicy`。EKS 只會替叢集建立時指定的 node role 自動建這個 access entry；NodeClass 沿用同一個 role 就不用另外建。
6. **Auto Mode 原生的 TargetGroupBinding 會在生命週期裡刪掉 target group**（使用者查證），所以模式 T 改用 AWS Load Balancer Controller 的 `elbv2.k8s.aws/v1beta1` TargetGroupBinding。`eks-cluster` 開 Auto Mode 時一定會開 elastic load balancing 能力（`modules/eks-cluster/variables.tf:245`），兩個 controller 會並存，範圍要分清楚（§10 風險 2）。
7. **private endpoint 只限制「要呼叫 Kubernetes API」的操作**。Helm、kubernetes provider 要從 VPC 或已連通的網路執行；只呼叫 AWS API 的 Terraform（建 EKS、IAM、access entry、Pod Identity association）不受影響，可以照舊在任何地方跑。執行 Helm 的身分還要有對應的 access entry 與 RBAC。
8. **`eks-cluster` 目前的 managed node group 不設 node SG**（`modules/eks-cluster/nodes.tf:1-40` 的 launch template 沒有 `vpc_security_group_ids`）。example3 不用 managed node group，這點不影響；node 與 pod 的 SG 都由 NodeClass 指定。
9. **`eks-addons` 目前只有 Karpenter 用的預設 NodePool**（`modules/eks-addons/charts/karpenter-defaults`），沒有 Auto Mode 的 NodeClass（`eks.amazonaws.com/v1`）與 NodePool，要補（§5）。
10. **repo 的 module 不互相引用**（沒有任何 module 有 `module` 區塊）。`eks-workload-alarms` 如果用 `source = "../metric-alarm"` 組合，HCP 只打包單一目錄、`vendor-modules.sh` 一次只複製一個 module，都會抓不到；改用 registry 位址又會讓 vendoring 到客戶環境時需要我們的 token。§9 W1 列為待決。

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
| E11 | stack 順序 | `eks-cluster`、`eks-addons` 放在 `bridge` 之後。這不是永久限制：叢集可以另外發布版本化的 EKS 合約給其他專案用（§7） |
| E12 | 其他 stack | `agent`、`operation`、`bridge` 照搬，只改 SSM 合約的 key；改完要逐一驗證 producer 與 consumer 的合約相容（§7） |
| E13 | helm lock hash | 使用者在自己的終端機跑 `terraform providers lock` |
| E14 | 資源擁有者 | 每一種資源只有一個擁有者，見 §4 |

### 3.2 我的判斷，使用者還沒表示意見

- **K1 node SG 另建，不放進 cluster SG**：`network` 新增一個 `node` SG，NodeClass 的 `securityGroupSelectorTerms` 選 EKS 建的 cluster SG 加上這個 `node` SG。`app`↔`node` 的規則都在 `network` 裡定義，不會出現「`network` 要讀 `eks-cluster` 建的 cluster SG」的跨 stack 循環（planner 指出的問題）。
- **K2 pod subnet 沿用 `app` tier**：node 與 pod 都選 `app` subnet（`network/vpc.tf:6`，每個 AZ 一個 /19，空間足夠），靠不同的 tag 區分。node 與 pod 能不能選同一個 subnet，文件沒有明說，**未確認**；不行的話在 `vpc_subnets` 加一個 `pod` tier。
- **K3 一組 `app` NodeClass／NodePool 給 api 與 worker**：理由見 §2 第 1 點。系統元件（LB Controller、KEDA、CloudWatch agent）另一組 `system` NodeClass／NodePool，用 node SG、不掛 `app` SG。內建的 `general-purpose`、`system` NodePool 都關掉（`auto_mode.node_pools = []`）。
- **K4 NodeClass 沿用叢集的 node role**：EKS 會自動建 access entry（§2 第 5 點），不用另外建。
- **K5 NetworkPolicy 預設 `DefaultDeny`**：namespace 內的放行規則放在 CI 的 chart 裡（§4），平台只開 controller、設預設值。CoreDNS 在 Auto Mode 是每台 node 本機跑，IP 由 service CIDR 推得（`.10`），chart 要放行。
- **K6 範本不建 CI runner**：README 寫清楚 Helm 要在 VPC 內執行、runner 的身分要哪些 access entry；建 runner（self-hosted runner、VPC 內的 CodeBuild）留給使用範本的專案。
- **K7 KEDA 的 IAM policy 放進 `eks-iam-policies`**：跟 LB Controller、Karpenter 一樣，由無資源的 module 輸出，`iam` stack 用 `iam-role` 建 role。
- **K8 斷路器關閉時不建任何資源**：`loadbalancer` 加一個 `canary` 物件，預設 `null`。有給才建第二個 target group、加權 rule 與 `lb-traffic-breaker`（Lambda 映像由使用者自己 build，v3 的決策不變）。

## 4. 資源擁有者

同一種資源只能有一個擁有者，兩個 module 或兩條部署流程都可能管理同一個東西，是這次最要避免的事。

| 層級 | 管理範圍 | 怎麼執行 |
|---|---|---|
| `eks-cluster`（module 與同名 stack） | EKS 叢集、access entry（叢集管理者、`eks-addons` 的 apply 身分、CI 部署身分）、Pod Identity association、輸出合約 | 只呼叫 AWS API，任何地方都能跑 |
| `iam` stack | cluster role、node role、api／worker 的 Pod Identity role、LB Controller、KEDA、CloudWatch agent 的 role | 只呼叫 AWS API |
| `eks-addons`（module 與同名 stack） | NodeClass／NodePool、namespace、NetworkPolicy controller 啟用、KEDA、AWS Load Balancer Controller、CloudWatch 採集 | Helm，要在 VPC 內 |
| CI 與範例 chart | api、worker 的 Deployment、ServiceAccount、Service、TargetGroupBinding、KEDA ScaledObject、應用程式的 NetworkPolicy | Helm，要在 VPC 內 |
| `loadbalancer` stack | ALB、listener、rule、target group、WAF、access log，斷路器（預設關閉） | 只呼叫 AWS API |
| `eks-workload-alarms`（`postdeploy` stack 呼叫） | api、worker 的標準告警 | 只呼叫 AWS API |

幾條要寫進 chart 與 README 的界線：

- TargetGroupBinding 不能帶 `networking` 區塊，不然 LB Controller 會改 Terraform 擁有的 SG 規則。
- chart 不建 Ingress、`type: LoadBalancer` 的 Service；ALB 只有 Terraform 建。
- ServiceAccount 名稱與 namespace 由 Terraform 決定、寫進 SSM，chart 照讀，不能自己取名，否則 Pod Identity association 對不上。

## 5. Module 變更

| module | 版本 | 內容 | 狀態 |
|---|---|---|---|
| `eks-addons` | 0.1.0 → 0.2.0 | Auto Mode 的 NodeClass／NodePool（本地 chart，`eks.amazonaws.com/v1`，含 Pod subnet／Pod SG 與 `networkPolicy` 欄位）；`amazon-vpc-cni` ConfigMap 啟用 NetworkPolicy controller；KEDA；CloudWatch 採集 | 要做 |
| `eks-iam-policies` | 0.1.0 → 0.2.0 | 輸出 KEDA 讀 CloudWatch 指標的 policy（K7） | 要做 |
| `eks-workload-alarms` | 新，0.1.0 | api、worker 的標準告警（§8） | 要做，做法見 §9 W1 |
| `iam-role` | 0.3.0 → 0.4.0（如果需要） | managed policy 白名單加 `CloudWatchAgentServerPolicy` | 看 §9 W2 |
| `eks-cluster` | 0.1.0 → 0.2.0（如果需要） | 確認 `auto_mode.node_pools = []` 能關掉內建 NodePool、輸出 cluster SG 與 service CIDR 給 NodeClass 與 NetworkPolicy 用 | C1 先查證，不需要就不改 |
| `vpc` | 0.2.0（已發） | subnet tag，給 NodeClass 的 selector 用 | example3 從 0.1.0 升上來 |

## 6. example3 的 stack

ORDER：

```
containerimage foundation network database iam bridge eks-cluster eks-addons loadbalancer agent application operation postdeploy
```

| stack | 跟 example2 比 |
|---|---|
| `containerimage`、`foundation`、`database`、`agent`、`operation` | 照搬（E12）；`containerimage` 只改描述文字 |
| `network` | `vpc` 升 0.2.0、`app` subnet 加 NodeClass 用的 tag；新增 `node` SG（K1）；`app` SG 加 node↔pod 需要的規則（kubelet 探測、DNS，**未實測**）；`nat_mode = "none"` 時加 EKS 需要的 interface endpoint（v3 §5 第 1 步的清單，再加 KEDA 讀指標用的 `monitoring`，**完整性未確認**） |
| `iam` | 拿掉 `ecs_execution`、`api_task`、`worker_task` 與 ECS Exec 權限（`iam/roles.tf:6-17`、`iam/policies.tf`）；新增 §4 列的 role |
| `bridge` | 轉發的 key 從三個 ECS role 換成 `api_pod_role_arn`、`worker_pod_role_arn` |
| `eks-cluster`（新） | 叢集（private endpoint、Auto Mode、內建 NodePool 關閉）、access entry、Pod Identity association、secrets 加密的 KMS key |
| `eks-addons`（新） | 呼叫 `eks-addons` 0.2.0；helm provider 由 SSM 讀到的 endpoint 與 CA 設定，用 `aws eks get-token` |
| `loadbalancer` | 不變的部分：ALB、WAF、origin-verify、access log、`api` target group（已經是 `ip` 類型，`loadbalancer/alb.tf:61-67`）；新增 `canary`（K8） |
| `application` | 從「建 ECS service」改成「發布部署合約」：不建任何資源，只把 chart 需要的值寫進 SSM（§7） |
| `postdeploy` | `ecs-service-alarms` 換成 `eks-workload-alarms`；log 告警改看 Container Insights 的 `application` log group |

## 7. SSM 合約

| stack | 拿掉 | 新增 |
|---|---|---|
| `iam` | `ecs_execution_role_arn`、`api_task_role_arn`、`worker_task_role_arn` | `eks_cluster_role_arn`、`eks_node_role_arn`、`api_pod_role_arn`、`worker_pod_role_arn`、`lb_controller_role_arn`、`keda_role_arn`、`cloudwatch_agent_role_arn` |
| `bridge`（tree B） | 三個 ECS role | `api_pod_role_arn`、`worker_pod_role_arn` |
| `eks-cluster` | — | `contract_version`、`cluster_name`、`cluster_endpoint`、`cluster_ca_data`、`cluster_sg_id`、`service_cidr`、`app_namespace`、`api_service_account`、`worker_service_account` |
| `application` | `cluster_name`、`*_service_name`、`*_log_group_name` | `api_environment_json`、`worker_environment_json`、`api_target_group_arn`（轉發，讓 CI 只讀一個前綴）、image repository URL、副本數上下限、`stream_length_cap` |

- `eks-cluster` 的 key 帶 `contract_version`，欄位有不相容的變動才升版。其他專案要共用這個叢集時讀這組 key，不必經過 `bridge`；E11 的順序只是 example3 自己的 apply 順序。
- E12 的「只改 key」要實際驗證：每個 phase 結束跑 `check-ssm-contract.sh`，並逐一比對 consumer 讀的 key、型別（String／StringList／JSON）與 producer 發布的一致。
- 環境變數只放 secret 的 ARN，不放 secret 值（跟 example2 `application/environment.tf` 一樣）。`tcp_keepalive_*` 從 ECS 的 `system_controls` 改成 pod 的 `securityContext.sysctls`，chart 負責。

## 8. 告警

`eks-workload-alarms` 對每個工作負載建：

- ALB target group：5xx、p95 延遲、健康主機數（只有 api）。
- Container Insights：pod 重啟次數、執行中 pod 數低於下限、CPU 與記憶體使用率。
- worker：stream backlog（沿用 example2 的指標）。

Container Insights 的指標要 CloudWatch 採集元件裝好才有（`eks-addons`）。指標名稱與維度在 C1 對照 AWS 文件確認。

## 9. 待決

| # | 問題 | 選項 | 建議 |
|---|---|---|---|
| W1 | `eks-workload-alarms` 怎麼「組合既有 metric-alarm」 | (a) module 內直接建 `aws_cloudwatch_metric_alarm`，告警的寫法與預設值照 `metric-alarm`、`ecs-service-alarms`（後者就是直接建資源，`modules/ecs-service-alarms/main.tf:181`）；(b) module 內呼叫 `metric-alarm`，打破 repo「module 不互相引用」的慣例，HCP 與 vendoring 都要另外處理 | (a) |
| W2 | CloudWatch 採集的 IAM | (a) `iam-role` 白名單加 `CloudWatchAgentServerPolicy`；(b) 用 inline policy 寫同樣的權限 | (a)，跟 v3 處理 EKS managed policy 的方式一致 |
| W3 | CloudWatch 採集用什麼裝 | (a) `eks-addons` 用 Helm 裝 `amazon-cloudwatch-observability` chart；(b) `eks-cluster` 的 `addons` 裝同名 EKS add-on（只呼叫 AWS API，但擁有者表把採集放在 `eks-addons`） | (a)，照 §4 的擁有者表；Helm chart 的版本與參數在 C1 查證 |
| W4 | NetworkPolicy 預設值 | `DefaultDeny` 或 `DefaultAllow` | `DefaultDeny`（K5） |

## 10. 風險與 mock 驗不到的事

1. **node 與 pod 選同一個 subnet 行不行**（K2）。不行就要加 `pod` tier，`network` 的 CIDR 規劃要改。
2. **兩個 TargetGroupBinding controller 並存**：Auto Mode 的 load balancing 能力關不掉，LB Controller 又另外裝。要確認兩者不會搶同一個資源，以及 LB Controller 的 webhook 不會影響 Auto Mode。**未確認**。
3. **`app` SG 要補的規則**：kubelet 探測 pod、pod 查 node 上的 CoreDNS，都是 VPC 內的流量，會經過 Pod SG。少了會導致探測失敗、DNS 失敗，mock 測不出來。
4. **Pod Identity association 早於 namespace 與 ServiceAccount 存在**（v3 §6 已列）。
5. **LB Controller 的官方 policy 能不能對 Terraform 建的 target group 做 `RegisterTargets`**。
6. **helm provider 用 SSM 讀到的值設定**，mock 測試與真實 plan 是否都能過。
7. **no-NAT 時的 interface endpoint 是否齊全**（Auto Mode、KEDA、CloudWatch agent 都會打 AWS API）。
8. **KEDA 依 CloudWatch 指標擴縮，跟 ECS 的 step scaling 對長連線（SSE）的行為是否一樣**。
9. **Container Insights 包了一層之後，`$.event` 這類 log filter 還能不能比對**（`postdeploy/log-alarms.tf`）。
10. **Kubernetes 版本**：placeholder 選目前仍在標準支援的版本（1.35 以上），C4 再查。
11. **保密**：example3 是從 example2 複製，只能帶 example2 已有的字串；每個 phase 都做來源字串的反向比對（[`../v2/integration-playbook.md`](../v2/integration-playbook.md)）。

## 11. 來源

- Create a Node Class for Amazon EKS（含〈Separate subnets and security groups for Pods〉）：<https://docs.aws.amazon.com/eks/latest/userguide/create-node-class.html>
- Use Network Policies with EKS Auto Mode：<https://docs.aws.amazon.com/eks/latest/userguide/auto-net-pol.html>
- Auto Mode 原生 TargetGroupBinding 的生命週期、private endpoint 的影響範圍：使用者 2026-10-22 查證（docs.aws.amazon.com、Amazon EKS 使用者指南）
- v3 的 EKS 決策：[`../v3/design-docs.md`](../v3/design-docs.md)
- 範本整合流程與保密規則：[`../v2/integration-playbook.md`](../v2/integration-playbook.md)
