# infra-platform v3 設計文件：EC2、EKS、ALB／NLB 權重分流與斷路器

> 狀態：設計草案，等使用者審閱（§3.1 已拍板，§3.2 是 planner 的判斷）。審過才進實作，步驟見 [`implement-process.md`](./implement-process.md)。
> 範圍：新增 EC2 主機、EKS（使用者能用 Helm 部署應用）、ALB 與 NLB 的權重分流（金絲雀）與斷路器（自動降級回舊系統）需要的 module。這次只寫設計，不寫 module 程式碼，也不改範本。
> 文中路徑除非特別註明，都是 repo 內相對路徑。「v1 §x.y」指 [`../v1/design-docs.md`](../v1/design-docs.md)，「v2 §x.y」指 [`../v2/design-docs.md`](../v2/design-docs.md)。
> 版本號與 AWS 行為是 2026-10-21 查證的結果，來源列在 §8。標「未確認」的要在實作或真實環境驗證。

## 1. 結論

新增 8 個 module、擴充 3 個，再補一組 `lambda-function` 的測試：

- 新 module（各發 `0.1.0`）：`ec2-instance`、`ec2-asg`、`nlb`、`lb-traffic-breaker`、`iam-oidc-provider`、`eks-iam-policies`、`eks-cluster`、`eks-addons`。registry 從 32 個 module 變 40 個。
- 擴充（MINOR）：`iam-role` 0.2.0 → 0.3.0（managed policy 白名單、Pod Identity 與 IRSA 的 trust）、`alb` 0.3.0 → 0.4.0（加權 forward、外部 target group、stickiness、`instance` target）、`vpc` 0.1.0 → 0.2.0（每個 tier 的 subnet 可以加 tag）。預設值維持原本行為，既有 tests 不改就要全過。
- `lambda-function` 只補測試：principal `lambda.alarms.cloudwatch.amazonaws.com` 目前沒有測試涵蓋（§4.1）。

權重分流與斷路器有兩種模式，同一條 listener rule 只能用其中一種（D9）：

| 模式 | 誰擁有 LB、listener、rule、權重 | 後端怎麼掛 | 斷路器 | 適用 |
|---|---|---|---|---|
| T（預設） | Terraform（`alb`、`nlb`） | EKS 的 Pod 用 TargetGroupBinding 註冊；EC2、ECS 直接用 target group | A'：alarm 觸發 Lambda，把權重改成舊系統 100% | 舊系統在 EC2、ECS 或另一個 EKS 服務，新系統在 EKS、ECS 或 EC2 |
| K | AWS Load Balancer Controller（Ingress 或 Service） | Ingress 的 `actions.<name>` annotation，或 Argo Rollouts 注入 | C：Argo Rollouts 依 CloudWatch 5xx 自動回退 | 新舊兩個版本都在同一個 EKS 叢集 |

ALB 可以完全對標：金絲雀用加權 target group，斷路器看新系統 target group 的 5xx 錯誤率與健康主機數。NLB 只能部分對標：金絲雀一樣能做（2025-11 起支援加權 target group），但斷路器只看得到健康主機數與使用者自己發的 CloudWatch 指標，看不到 HTTP 錯誤（§2 第 5、6 點）。

EKS 拆成兩個 module、兩個 stack、兩次 apply：`eks-cluster` 只建 AWS 資源，`eks-addons` 只用 helm provider 裝叢集裡的元件。kubernetes provider 文件明說叢集與叢集內資源不要在同一次 apply 建（§2 第 10 點）。

全部只做離線驗證：`fmt`、`tflint`、`init -backend=false`、`validate`、`terraform test` 搭配 `mock_provider`。不做 `plan`、`apply`、帶 backend 的 `init`，也不碰任何 AWS 帳號。

不做：

- 方案 A（靠 listener rule 優先權在新服務不健康時往下掉到舊系統規則）：ALB 不會這樣運作（§2 第 1、2 點）。
- 方案 B（Istio outlier detection）。
- 範本整合（§5 只寫建議）。
- 斷路器觸發後自動把權重調回去：回復一律由人改 tfvars 再 apply（J8）。
- `ec2-instance` 的 public IP 與 SSH key pair（J11）。
- Lambda 映像的 build 與推送：repo 提供程式碼與 Dockerfile，使用者自己 build、推到 ECR（D11）。
- 真實環境的部署驗證。

## 2. 查證時發現、會影響設計的事

1. ALB 的 listener rule 只依條件比對，照 priority 由小到大評估，健康狀態不是條件的一種，所以新服務的 target group 不健康時，請求不會往下掉到下一條規則。官方沒有一句話直接寫「不會 fall through」，這是依規則評估方式推得的，信心高。
2. ALB 的 target group 裡全部 target 都不健康時會 fail open，照樣把請求送給這些 target。原文：「If a target group contains only unhealthy registered targets, the load balancer routes requests to all those targets, regardless of their health status.」
3. 加權 forward 的其中一個 target group 沒有健康 target 時，ALB 不會自動把流量轉給其他 target group。原文：「the load balancer does not automatically fail over to a target group with healthy targets.」所以斷路器一定要主動改權重。
4. ALB 一個 forward action 最多 5 個 target group（不可調），權重 0–999。多個 target group 裡有任何一個開了 stickiness，就必須開 target group stickiness，cookie 是 `AWSALBTG`；aws provider 的 `stickiness.duration` 是必填，範圍 1–604800 秒。
5. NLB 從 2025-11-19 起支援在 listener 的 forward 放多個加權 target group，權重 0–999。改權重只影響新連線，既有連線照舊，生效最多約 3 分鐘。同一個 listener 裡的 target group 必須是同一種 protocol 與 IP 版本，TLS listener 不支援 target group stickiness。default action 的 target group 上限官方沒有明列（listener rule action 是 5），provider 限制 1–5。
6. NLB 沒有 HTTP 狀態碼指標。可以依 target group 拆的只有 `HealthyHostCount`、`UnHealthyHostCount`、`NewFlowCount`、`ActiveFlowCount`；`TCP_Target_Reset_Count` 只有 `LoadBalancer` 與 `AvailabilityZone` 維度，沒辦法歸到新系統。
7. NLB 的 DNS failover 跟 ALB 相反：NLB 掛了多個 target group 時，只要其中一個在某個 zone 不健康，就會觸發 DNS failover，即使另一個 target group 在那個 zone 是健康的。`dns_failover.minimum_healthy_targets.count` 預設 1。結果是新系統的 target group 在某個 AZ 沒有健康 target，整個 zone 的 NLB 節點都會被移出 DNS，連舊系統的流量也受影響。ALB 則是同一個 zone 只要還有一個 target group 健康，DNS 健康檢查就算通過。
8. `target_group_health` 的 `unhealthy_state_routing` 與 `dns_failover` 都只在單一 target group 的單一 zone 內生效：前者是提早 fail open，後者是把 zone 的 LB 節點移出 DNS。兩者都不能拿來「切回舊系統」。
9. AWS Load Balancer Controller 會在 reconcile 時把 out-of-band 的修改改回去（Ingress、Service 有變動時觸發，另外有 `--sync-period`，預設 10 小時）。所以 Lambda 不能去改 controller 管的 ALB 規則。官方的替代做法是 LB 與 listener 完全在 Kubernetes 外面建，controller 只透過 TargetGroupBinding 註冊 target。
10. kubernetes provider 文件寫明叢集與叢集裡的資源「SHOULD NOT be created in the same Terraform module」，並建議分開 apply。helm provider 走同一套認證，所以 `eks-addons` 要在另一個 stack。
11. Argo Rollouts 的 stable 與 canary 是同一個 Rollout 底下的兩個 ReplicaSet，所以方案 C 只能用在「新舊都在 EKS、同一個服務換版本」。舊系統在 EC2、ECS 的遷移只能用 A'。Argo Rollouts 核心不支援 NLB；Gateway API plugin 能用 TCPRoute 做，但 AWS Load Balancer Controller 不在那個 plugin 的已測試清單上（未確認）。
12. Fargate 不支援 EKS Pod Identity，Fargate 上的 Pod 要存取 AWS 只能用 IRSA。Fargate 也不支援 DaemonSet、privileged、HostNetwork、EBS、Fargate Spot。
13. `aws_eks_cluster` 的 `bootstrap_self_managed_addons` 預設 `true`、改了會 ForceNew，而 Auto Mode 要求它是 `false`。`access_config.bootstrap_cluster_creator_admin_permissions` 預設 `true`、也是 ForceNew；官方 best practice 建議設 `false`，另外明確建 admin 的 access entry。`encryption_config` 開了就不能關，移除會 ForceNew。
14. Auto Mode 要求 `compute_config.enabled`、`kubernetes_network_config.elastic_load_balancing.enabled`、`storage_config.block_storage.enabled` 三者同時開或同時關，`authentication_mode` 必須是 `API`。Auto Mode 只能用 Bottlerocket，節點最長存活 21 天，不能 SSH 或 SSM 進節點。
15. Auto Mode 可以跟 managed node group 共存（官方 FAQ）。跟自管 Karpenter 共用 `nodepools.karpenter.sh`、`nodeclaims.karpenter.sh` CRD，官方只把並存當成遷移期。跟 Fargate 能不能長期共存，官方沒有明說（未確認）。Auto Mode 的 zonal shift 支援，兩份官方文件說法矛盾（未確認）。
16. AL2 的 EKS AMI 從 2025-11-26 起不再發布，1.33 以後只有 AL2023 與 Bottlerocket。
17. EKS 的 Kubernetes 版本：standard support 是 1.37、1.36、1.35、1.34（1.34 的 standard 到 2026-12-02），extended support 是 1.33、1.32、1.31（1.31 到 2026-11-26 完全結束）。生命週期是 standard 14 個月加 extended 12 個月，`upgrade_policy.support_type` 的 AWS 預設是 `EXTENDED`，會另外計費。
18. Karpenter controller 建議跑在 managed node group 或 Fargate；放在 Fargate 就要改用 IRSA。private cluster 需要 `settings.isolatedVPC=true`，而且 IAM API 沒有 VPC endpoint，EC2NodeClass 要改用預先建好的 `spec.instanceProfile`。
19. 本 repo 的靜態規則會擋掉直接寫的做法（v1 §5.6、`scripts/validate.sh`）：
    - S4-a：`aws_iam_*` 只能在 `iam-role`、`iam-role-policy`。EKS 的 cluster role、node role、Pod Identity role、OIDC provider、instance profile 都要走 module。
    - S4-b：security group 只能在 `security-group`、`vpc-interface-endpoints`。
    - S3：`data "aws_ssm_parameter"` 只能在 `ssm-read`，所以不能讀 AL2023 或 EKS AMI 的公開 SSM 參數。
    - `iam-role` 的 trust 目前寫死 `sts:AssumeRole` 與 `Service` principal（`modules/iam-role/main.tf`），Pod Identity 需要 `sts:TagSession`，IRSA 需要 `Federated` 與 `sts:AssumeRoleWithWebIdentity`。
    - `alb` 的 rule 只能 forward 到單一 target group，target group 寫死 `ip`、`HTTP`（`modules/alb/main.tf`）。
    - `vpc` 的 subnet tag 只有 `var.tags` 加 `Name`，不能依 tier 加 `kubernetes.io/role/elb`（`modules/vpc/main.tf`）。
    - `metric-alarm` 的 action 只接 SNS ARN（`modules/metric-alarm/variables.tf`）。
    - repo 還沒有任何 module 用 helm 或 kubernetes provider。

## 3. 決策

### 3.1 使用者拍板（2026-10-21）

| # | 決策 | 理由 |
|---|---|---|
| D1 | 這次先寫設計文件，放在 `docs/design/v3`；審過再分 Phase 實作 | 範圍大，先對齊再動手 |
| D2 | 權重分流用 AWS Load Balancer Controller，ALB 與 NLB 都做；NLB 要對標 ALB 的金絲雀與斷路器 | 使用者要用 Helm 部署 EKS 應用，也要能從舊系統逐步切流量 |
| D3 | EKS 節點四種都支援：managed node group、Karpenter、Fargate profile、Auto Mode | 不同專案的成本與維運取捨不同 |
| D4 | EC2 做兩個 module：`ec2-instance`（單台）與 `ec2-asg`（launch template 加 Auto Scaling group） | 單台與可自動補機器的需求都有 |
| D5 | 斷路器做 A'（CloudWatch alarm 觸發 Lambda，把權重改回舊系統 100%）與 C（Argo Rollouts 依 CloudWatch 5xx 自動回退）。方案 A 不採用；方案 B（Istio）不做 | ALB 不會因 target group 不健康而換規則，加權 forward 也不會自動 failover（§2 第 1–3 點），只能主動改權重 |
| D6 | Helm 元件放在獨立的 `eks-addons` module，跟 `eks-cluster` 分開 | 叢集與叢集內資源不能同一次 apply（§2 第 10 點） |
| D7 | Pod 的 AWS 權限用 EKS Pod Identity；Fargate 例外用 IRSA | Pod Identity 是 AWS 目前推薦的做法；Fargate 不支援 Pod Identity（§2 第 12 點） |
| D8 | `iam-role` 允許掛 AWS managed policy，但只限白名單（§4.1） | EKS 的 cluster role、node role、Auto Mode、EBS CSI 以 managed policy 為標準，AWS 會自己更新內容；改寫成 inline 容易漏權限 |
| D9 | LB 擁有者分成兩種模式：T（預設，Terraform 擁有 LB、listener、rule、權重，Pod 用 TargetGroupBinding 註冊，配 A'，可以混舊系統的 EC2、ECS target group）與 K（controller 管 Ingress 或 Service，配 Argo Rollouts）。同一條規則不能兩種都用 | controller 會把 Lambda 的修改改回去，Argo Rollouts 又需要 controller 管 Ingress（§2 第 9、11 點） |
| D10 | `eks-cluster` 的 `support_type` 預設 `EXTENDED` | 升級壓力小；過了 standard 期會額外計費，README 要寫清楚 |
| D11 | 斷路器的 Lambda 用 container image：repo 提供程式碼與 Dockerfile，使用者自己 build 並推到 ECR，再把 image URI 傳給 `lambda-function` | `lambda-function` 只支援 container image，不新增 provider |
| D12 | NLB 的斷路器預設看新系統 target group 的 `HealthyHostCount`，另外可以傳入應用程式自己發的 CloudWatch 指標當觸發條件；README 寫明跟 ALB 的差異 | NLB 沒有 HTTP 5xx（§2 第 6 點） |
| D13 | Karpenter 的預設 NodePool 與 EC2NodeClass 由 `eks-addons` 提供一組，可以關掉自己管 | 開箱就能用，又不綁死 |
| D14 | `nlb` 的 listener 放了多個 target group 時，每個 target group 都必須把 `dns_failover` 設成 `"off"`，validation 擋；單一 target group 時維持 AWS 預設 | 避免新系統的 target group 在某個 AZ 沒有健康 target 時，整個 zone 被移出 DNS、拖累舊系統（§2 第 7 點） |
| D15 | LB Controller、Karpenter controller、Argo Rollouts 的官方 IAM policy 由 module 當輸出提供，版本跟 chart 綁在一起 | 不用範本的人也拿得到正確版本的 policy；做法見 J14 |
| D16 | `ec2-instance` 的 `StatusCheckFailed_System` 告警可以不建：`sns_topic_arns` 預設 `[]`，空的就不建告警 | 使用者決定。這是 repo「會建告警的 module，`sns_topic_arns` 必填」慣例（v1 §4.1）的例外，README 要寫明 |
| D17 | Auto Mode 與 Fargate 可以同時用，不用 validation 擋；README 寫明官方沒有說能長期共存 | 使用者決定，風險由使用者自負（R13） |

### 3.2 planner 判斷、使用者未反對

| # | 決策 |
|---|---|
| J1 | 新 module 命名：`ec2-instance`、`ec2-asg`、`nlb`、`lb-traffic-breaker`、`iam-oidc-provider`、`eks-iam-policies`、`eks-cluster`、`eks-addons`，跟既有的 `alb`、`ec2-bastion`、`iam-role` 一致 |
| J2 | EKS 的節點模式由輸入決定，不用 `enable_xxx`（v1 §4.1）：`managed_node_groups`、`fargate_profiles` 是 map，空的就不建；`auto_mode`、`karpenter` 是物件，null 就不建。互斥規則用 validation 擋：`auto_mode` 與 `karpenter` 互斥（CRD 衝突）；`karpenter` 需要至少一個 managed node group 跑 controller；四種至少要有一種 |
| J3 | `eks-cluster` 固定 `bootstrap_self_managed_addons = false`、`authentication_mode = "API"`、`bootstrap_cluster_creator_admin_permissions = false`，不提供開關（三個都是 ForceNew，§2 第 13 點）。所以 `access_entries` 至少要有一個 cluster scope 的 `AmazonEKSClusterAdminPolicy`，給跑 apply 的 role，validation 擋 |
| J4 | 叢集與叢集內元件分兩個 stack、兩次 apply：`eks-cluster` 在前，`eks-addons` 在後 |
| J5 | `eks-addons` 只用 helm provider。Karpenter 的預設 NodePool、EC2NodeClass 與應用程式的 namespace，用 module 內附的本地 chart 經 `helm_release` 安裝，不用 `kubernetes_manifest`（它在 plan 時就要連叢集讀 CRD） |
| J6 | metrics-server 用 EKS 的 community add-on，放在 `eks-cluster` 的 `addons`，不用 Helm。Auto Mode 的叢集也要裝 |
| J7 | 斷路器的 alarm 直接以 Lambda 當 action（principal `lambda.alarms.cloudwatch.amazonaws.com`，帶 `AWS:SourceAccount` 與 `AWS:SourceArn`），同時通知 SNS；不走 EventBridge，少一層資源 |
| J8 | Lambda 只做一件事：把指定規則的權重改成舊系統 100%、其他 0。不自動回復。回復一律照 runbook 改 tfvars 再 apply（R1） |
| J9 | 斷路器的 alarm 由 `lb-traffic-breaker` 自己建（`aws_cloudwatch_metric_alarm`），不呼叫 `metric-alarm`：module 不互相呼叫，而且 `metric-alarm` 的 action 只接 SNS |
| J10 | `vpc` 擴充每個 tier 的 subnet tag，用來加 `kubernetes.io/role/elb`、`kubernetes.io/role/internal-elb` 與 Karpenter 的 discovery tag。security group 的 discovery tag 用 `security-group` 既有的 `tags`（另外呼叫一次給節點用的 SG），不用擴充 |
| J11 | `ec2-instance` 跟 `ec2-bastion` 一樣：固定 IMDSv2、不給 public IP、沒有 `key_name`，只走 SSM Session Manager；對外流量經 ALB 或 NLB |
| J12 | （改由使用者拍板，見 D14） |
| J13 | Helm chart 版本固定預設值，由使用者覆寫：AWS Load Balancer Controller `3.6.0`、Karpenter `1.15.0`、Argo Rollouts `2.43.8`。EKS add-on 的版本由使用者給，不設預設（版本跟 Kubernetes 版本綁在一起） |
| J14 | D15 的做法：新增 `eks-iam-policies`，不建任何資源、只有輸出，依 chart 版本輸出 LB Controller、Karpenter controller、Argo Rollouts（CloudWatch analysis 用）的 policy JSON。IAM stack 在 `eks-cluster` 之前，呼叫 `eks-addons` 又要先設好 helm provider，所以 policy 不能放在 `eks-addons` 的輸出。role 仍由呼叫端用 `iam-role` 建，`eks-cluster`、`eks-addons` 只收 role ARN。LB Controller 的 policy 照官方 `iam_policy.json` 的 v3.6.0 版 |
| J15 | 斷路器 Lambda 的程式碼分成兩層：計算新 action 的純函式（只用 Python 標準函式庫，CI 用 `python3 -m unittest` 測）與呼叫 AWS API 的薄殼。CI 不 build Docker 映像 |

## 4. Module

慣例照 v1 §4.1、v2 §4 與 [`releasing-modules.md`](../../guides/releasing-modules.md)：

- 檔案：`main.tf`、`variables.tf`、`outputs.tf`、`versions.tf`、`README.md`、`CHANGELOG.md`、`examples/basic/`、`tests/*.tftest.hcl`。
- `versions.tf` 寫 `required_version = ">= 1.10"`、`aws >= 6.0, < 7.0`；用到較新的屬性時提高下限，並寫英文註解說明原因。不寫 provider、backend、lock 檔。
- module 不互相呼叫、不用 `enable_xxx` 開關、只收完整的 `name`；`tags` merge 上 `Name`。
- 只要建告警，`sns_topic_arns` 就是必填，`alarm_actions` 與 `ok_actions` 都接。例外是 `ec2-instance`（D16）。
- IAM 只在 `iam-role`、`iam-role-policy`、`iam-oidc-provider`（§4.3）；security group 只在 `security-group`。其他 module 只收 ARN 或 ID。
- `.tf` 的註解、description、error_message 用英文；README、CHANGELOG 用台灣繁體中文。
- 一個 commit 只動一個 module 目錄。每條 validation 都要有正反兩個 run，安全相關的負向測試不能省。

### 4.1 擴充既有 module

預設值維持原本行為：既有 tests 一個都不改就要全過。

**`iam-role` 0.2.0 → 0.3.0**

- `managed_policy_arns`（set(string)，預設 `[]`）→ `aws_iam_role_policy_attachment`。只接受白名單裡的 AWS managed policy，其他一律拒絕。白名單（依 §8 的來源）：
  - `AmazonEKSClusterPolicy`、`AmazonEKSComputePolicy`、`AmazonEKSBlockStoragePolicyV2`（Auto Mode 叫這個名稱，未確認是否就是 `AmazonEKSBlockStoragePolicy`）、`AmazonEKSLoadBalancingPolicy`、`AmazonEKSNetworkingPolicy`
  - `AmazonEKSWorkerNodePolicy`、`AmazonEKSWorkerNodeMinimalPolicy`、`AmazonEKS_CNI_Policy`、`AmazonEC2ContainerRegistryPullOnly`
  - `AmazonEKSFargatePodExecutionRolePolicy`
  - `AmazonEBSCSIDriverPolicyV2`
  - `AmazonSSMManagedInstanceCore`
  - ARN 格式 `arn:aws:iam::aws:policy/<name>`；`AmazonEBSCSIDriverPolicyV2` 等 service-role 類的實際路徑實作時核對（未確認）。
- `trust` 新增：
  - `tag_session`（bool，預設 `false`）：`true` 時 Action 變成 `["sts:AssumeRole", "sts:TagSession"]`。Auto Mode 的 cluster role 與 Pod Identity 都要。
  - `federated`（物件，預設 null）：`{ oidc_provider_arn, subject = "system:serviceaccount:<ns>:<sa>" }`，給 IRSA 用。有值時 statement 改成 `Federated` principal 加 `sts:AssumeRoleWithWebIdentity`，條件 `StringEquals` `<issuer>:sub` 與 `<issuer>:aud = sts.amazonaws.com`。`federated` 與 `service_principals` 只能二選一。
  - `service_principals` 放寬成可以是 `pods.eks.amazonaws.com`（已經符合 `*.amazonaws.com` 的格式，只要補測試）。
- tests：
  - 白名單內的 policy 會掛上；白名單外（含客戶自建的 policy ARN）被拒。
  - `tag_session` 預設時 trust 跟 0.2.0 完全相同。
  - Pod Identity role（`pods.eks.amazonaws.com` 加 `tag_session`）。
  - IRSA role 的 `sub`、`aud` 條件；`federated` 與 `service_principals` 同時給被拒；`subject` 格式不對被拒。
- README 的「刻意不做」與 v1 §4.14 的「不掛 AWS managed policy」改成「只掛白名單」，並寫明理由（D8）。

**`alb` 0.3.0 → 0.4.0**

- `target_groups` 新增 `target_type = optional(string, "ip")`，可以是 `ip` 或 `instance`（`ec2-asg` 用）。protocol 仍然固定 HTTP。
- `listener_rules` 新增 `forward = optional(object({ targets = map(object({ target_group = optional(string), target_group_arn = optional(string), weight })), stickiness_duration = optional(number) }))`：
  - `target_group` 指本 module 的 key，`target_group_arn` 是外部的 target group（例如舊系統、ECS、另一個 ALB 建的），兩者擇一。
  - 有 `forward` 時規則用 `action { type = "forward"  forward { target_group {...}  stickiness {...} } }`；沒有時維持原本單一 `target_group` 的寫法。`target_group` 與 `forward` 擇一。
  - validation：`targets` 1–5 個（ALB 上限，不可調）；`weight` 0–999；至少一個權重大於 0；`stickiness_duration` 1–604800；有任何一個本 module 的 target group 開了 stickiness 時，`stickiness_duration` 必填（§2 第 4 點）。
- `target_groups` 新增 `stickiness = optional(object({ duration }))`（`lb_cookie`），預設 null。
- 新增輸出 `listener_rule_arns`（map，key 同 `listener_rules`）與 `listener_arns`（`http`、`https`），給 `lb-traffic-breaker` 用。
- 權重寫在 tfvars 裡；斷路器改了權重之後，下次 apply 會改回 tfvars 的值（R1）。module 不加 `ignore_changes`：加了之後 tfvars 改權重也不會生效。
- tests：既有 5 個測試檔不改就要全過；加權 forward 的 target 數、權重、外部 ARN；`target_group` 與 `forward` 同時給被拒；超過 5 個被拒；權重全 0 被拒；`instance` target type。

**`vpc` 0.1.0 → 0.2.0**

- `subnets` 每個 tier 新增 `tags = optional(map(string), {})`，merge 在 `var.tags` 與 `Name` 之間（`Name` 仍然最後蓋上）。
- 用途：`public` tier 加 `kubernetes.io/role/elb = "1"`，`private` tier 加 `kubernetes.io/role/internal-elb = "1"` 與 `karpenter.sh/discovery = <cluster>`。LB Controller 不看 route table，沒有 tag 就找不到 subnet（§8）。
- tests：沒給 `tags` 時 subnet 的 tag 跟 0.1.0 相同；給了只套在那個 tier；`Name` 不能被覆寫。

**`lambda-function`（只補測試，不發版）**

- `permissions` 加一個 run：principal `lambda.alarms.cloudwatch.amazonaws.com`、`source_arn` 是 alarm ARN、`source_account` 有值，plan 成功。目前依 regex 應該可以通過，但沒有測試涵蓋。commit 用 `test(lambda-function): ...`，release-please 不會因此發版。

### 4.2 新 module（各發 0.1.0）

| module | 主要輸入 | 主要輸出 | 必寫的 tests |
|---|---|---|---|
| `ec2-instance` | `name`、`subnet_id`、`security_group_ids`（至少 1 個）、`instance_profile_name`、`instance_type`、`architecture = "arm64"`、`ami_id`（預設 null，null 時找最新 AL2023）、`root_volume = { size = 20, kms_key_arn = null }`、`ebs_volumes = map(object({ device_name, size, type = "gp3", kms_key_arn = null }))`、`user_data`（預設 null）、`disable_api_termination = true`、`sns_topic_arns`（預設 `[]`，空的就不建告警，D16）、`tags` | `instance_id`、`private_ip`、`ami_id`、`alarm_arns`（沒建時是空 map） | IMDSv2 required、hop limit 1、不配 public IP、root 與資料碟都加密；`instance_type` 與 `architecture` 不搭被拒；`user_data` 出現像 secret 的字樣被拒（照 `lambda-function` 的規則）；給了 `sns_topic_arns` 時 `StatusCheckFailed_System` 告警的 action 有 recover 與 SNS；沒給時沒有告警 |
| `ec2-asg` | `name`、`subnet_ids`、`security_group_ids`、`instance_profile_name`、`instance_types`（list，第一個是主要型號）、`architecture`、`ami_id`（同上）、`root_volume`、`user_data`、`min_size`、`max_size`、`desired_capacity`、`spot`（物件，null 就全 on-demand：`on_demand_base_capacity = 1`、`on_demand_percentage_above_base = 100`、`allocation_strategy = "price-capacity-optimized"`）、`target_group_arns`（預設 `[]`）、`health_check_grace_period = 300`、`instance_refresh = { min_healthy_percentage = 90 }`、`cpu_target`（預設 null，有值才建 target tracking）、`tags` | `asg_name`、`asg_arn`、`launch_template_id`、`launch_template_latest_version` | launch template 固定 IMDSv2、不配 public IP、EBS 加密；`target_group_arns` 非空時 `health_check_type = "ELB"`；`min <= desired <= max`；`spot` 為 null 時沒有 mixed instances policy；`desired_capacity` 用 `ignore_changes`，讓 scaling policy 管；`tags` 帶到 instance（`propagate_at_launch`） |
| `nlb` | `name`、`internal = true`、`subnet_ids`（至少 2 個）、`security_group_ids`（至少 1 個）、`cross_zone = true`、`deletion_protection = true`、`access_logs`（可選：`bucket`、`prefix`）、`vpc_id`、`target_groups = map(object({ port, protocol = "TCP", target_type = "ip", deregistration_delay = 300, preserve_client_ip = null, health_check = optional(...), stickiness = optional(bool, false), dns_failover = optional(string, "1") }))`、`listeners = map(object({ port, protocol = "TCP", certificate_arn = null, ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06", alpn_policy = null, targets = map(object({ target_group = optional(string), target_group_arn = optional(string), weight })) }))`、`sns_topic_arns`（必填）、`tags` | `nlb_arn`、`nlb_arn_suffix`、`dns_name`、`zone_id`、`listener_arns`、`target_group_arns`、`target_group_arn_suffixes`、`alarm_arns` | 多個 target group 的 listener 每個 target group 都要 `dns_failover = "off"`（J12）；同一個 listener 的 target group protocol 一致；TLS listener 必須給憑證，而且不能有開 stickiness 的 target group；`targets` 1–5 個、權重 0–999、至少一個大於 0；不准沒有 security group（NLB 的 SG 只能在建立時加，未確認）；每個 target group 一條 `UnHealthyHostCount` 告警 |
| `lb-traffic-breaker` | `name`、`load_balancer_type`（`application` 或 `network`）、`load_balancer_arn_suffix`、`breakers = map(object({ listener_arn = optional(string), rule_arn = optional(string), stable_target_group_arn, canary_target_group_arn_suffix, error_rate_percent = 5, min_requests = 50, min_healthy_hosts = 1, period = 60, evaluation_periods = 3, datapoints_to_alarm = 2, custom_metric = optional(object({ namespace, metric_name, dimensions, statistic, threshold, comparison_operator })) }))`、`lambda_function_arn`、`sns_topic_arns`（必填）、`tags` | `alarm_arns`、`alarm_names`、`lambda_config_json`（給 Lambda 的環境變數）、`lambda_permissions`（給 `lambda-function` 的 `permissions` 的 map） | ALB 有 5xx 錯誤率與健康主機數兩條；NLB 只有健康主機數與可選的自訂指標，給 5xx 參數被拒；`listener_arn` 與 `rule_arn` 擇一（NLB 只能 `listener_arn`）；alarm 的 `alarm_actions` 同時有 Lambda 與 SNS；5xx 錯誤率用 metric math 而且 `treat_missing_data = "notBreaching"`，健康主機數用 `"breaching"`；`lambda_permissions` 的 `source_arn` 是對應 alarm 的 ARN |
| `eks-iam-policies` | `cluster_name`、`region`、`account_id`、`partition = "aws"`、`karpenter = object({ node_role_arn, interruption_queue_name })`（預設 null）、`load_balancer_controller_version = "3.6.0"`、`karpenter_version = "1.15.0"` | `load_balancer_controller_policy_json`、`karpenter_controller_policy_json`（`karpenter` 為 null 時是 null）、`argo_rollouts_cloudwatch_policy_json` | 沒有任何 resource、也不需要 provider；輸出是合法 JSON；Karpenter 的 `iam:PassRole` 只限 `node_role_arn`；版本不在支援清單內被拒（module 只附它查證過的版本）；policy 長度記錄在 README（R5） |
| `iam-oidc-provider` | `issuer_url`（`eks-cluster` 的輸出）、`client_ids = ["sts.amazonaws.com"]`、`tags` | `arn`、`issuer`（去掉 `https://`） | 只接受 `https://oidc.eks.<region>.amazonaws.com/id/<id>` 格式；`client_ids` 預設值。只建 `aws_iam_openid_connect_provider`，只在有 Fargate 工作負載要 AWS 權限時才需要（D7） |
| `eks-cluster` | 見下方 | 見下方 | 見下方 |
| `eks-addons` | 見下方 | 見下方 | 見下方 |

**`ec2-instance`、`ec2-asg` 的共同設計**

- AMI 照 `ec2-bastion`：`data "aws_ami"`，owner `amazon`、AL2023、依 `architecture` 篩選（S3 不能讀 SSM 參數）。`ami_id` 有值就直接用。`ec2-instance` 用 `ignore_changes = [ami]`，`ec2-asg` 不需要，新 AMI 經 instance refresh 換上。
- 加密碟用帳號預設的 EBS KMS key，或 `kms_key_arn` 指定的 key。
- `user_data` 會以明文存在 state 與 launch template 裡，README 寫明不要放 secret。

**`lb-traffic-breaker` 與 Lambda**

運作方式：

1. 每個 `breakers` 的 key 對應一條「新系統 target group 出事就切回舊系統」的規則。
2. module 建 alarm，名稱 `<name>-<key>-<signal>`。alarm ARN 可以由名稱組出來，所以呼叫端可以在同一個 stack 先算好 `lambda_permissions` 給 `lambda-function`，不會有循環。
3. alarm 進入 ALARM 時，以非同步方式呼叫 Lambda（CloudWatch 保證每次狀態變化都會呼叫一次），同時送 SNS 通知人。
4. Lambda 讀 `BREAKER_CONFIG`（module 的 `lambda_config_json` 輸出，alarm 名稱對應到 listener 或 rule 與 stable target group），呼叫 `DescribeListeners` 或 `DescribeRules` 取得目前的 action，把 forward 裡 stable target group 的權重設成大於 0、其他設成 0，保留 stickiness 設定，再用 `ModifyListener` 或 `ModifyRule` 帶完整的 action 清單寫回（API 要求完整清單，§8）。
5. 冪等：目前已經是「只有 stable 有權重」就直接結束。成功後在 listener 或 rule 加 tag `traffic-breaker/tripped = <alarm name>`，方便從 console 與 runbook 辨識。

Lambda 的 IAM（由呼叫端用 `iam-role` 建；這份 policy 依 `breakers` 的 ARN 而定，所以不放進 `eks-iam-policies`）：

- `elasticloadbalancing:ModifyListener`、`ModifyRule`、`AddTags`：resource 限定到 `breakers` 裡的 listener 與 rule ARN。
- `elasticloadbalancing:DescribeListeners`、`DescribeRules`：只能 `*`。

Lambda 程式碼放在 `modules/lb-traffic-breaker/lambda/`：`breaker.py`（純函式，輸入 describe 的結果，輸出新的 action 清單）、`handler.py`（boto3 呼叫）、`test_breaker.py`、`Dockerfile`（AWS 的 Lambda Python base image，版本實作時決定並固定 digest）。README 寫 build 與推 ECR 的指令；映像 tag 不能是 `latest`（`lambda-function` 會擋）。

ALB 與 NLB 的差異（寫進 README）：

| 項目 | ALB | NLB |
|---|---|---|
| 觸發訊號 | 新系統 target group 的 5xx 錯誤率（`HTTPCode_Target_5XX_Count ÷ RequestCount`，請求數低於 `min_requests` 不算）、`HealthyHostCount < min_healthy_hosts` | `HealthyHostCount < min_healthy_hosts`、可選的自訂指標 |
| 看得到「連得上但回錯」 | 看得到 | 看不到，除非應用程式自己發指標 |
| 切回後的生效 | 下一個請求就照新權重 | 只影響新連線，最多約 3 分鐘；長連線不會被移走 |
| 能改的位置 | listener default action 或 rule | listener default action |

**`eks-cluster`**

主要輸入：

- 叢集：`name`、`kubernetes_version`（必填，不給預設）、`support_type = "EXTENDED"`（D10）、`subnet_ids`（至少 2 個 AZ）、`security_group_ids`（額外的 SG，預設 `[]`）、`endpoint_public_access = false`、`public_access_cidrs = []`（public 開啟時必填，不准 `0.0.0.0/0`）、`kms_key_arn`（必填，secrets 加密）、`cluster_role_arn`、`enabled_log_types = ["api", "audit", "authenticator"]`、`log_retention_days = 30`、`log_kms_key_arn`、`deletion_protection = true`、`zonal_shift = false`。
- 節點（J2）：
  - `managed_node_groups = map(object({ node_role_arn, subnet_ids = optional(...), ami_type = "AL2023_x86_64_STANDARD", instance_types, capacity_type = "ON_DEMAND", min_size, max_size, desired_size, disk_size = 50, disk_kms_key_arn = null, labels = {}, taints = [], max_unavailable_percentage = 33 }))`。module 為每個 node group 建 launch template：IMDSv2 required、hop limit 1（用 Pod Identity 時可以擋住 Pod 拿 node role，§8）、EBS gp3 加密。`desired_size` 用 `ignore_changes`。
  - `fargate_profiles = map(object({ pod_execution_role_arn, subnet_ids, selectors = list(object({ namespace, labels = {} })) }))`。subnet 只能是 private。
  - `auto_mode = object({ node_role_arn, node_pools = ["general-purpose", "system"] })`，預設 null。有值時三個 Auto Mode 設定一起打開。
  - `karpenter = object({ node_role_arn, controller_namespace = "kube-system", controller_service_account = "karpenter", controller_role_arn })`，預設 null。有值時 module 建 interruption 用的 SQS queue（retention 300 秒、SSE、拒絕非 TLS）、5 條 EventBridge 規則、node role 的 `EC2_LINUX` access entry、controller 的 Pod Identity association。
- add-on：`addons = map(object({ version, configuration_values = null, pod_identity_role_arn = null, service_account = null, resolve_conflicts_on_update = "OVERWRITE" }))`。非 Auto Mode 時，`vpc-cni`、`kube-proxy`、`coredns`、`eks-pod-identity-agent` 必須在裡面（validation）；Auto Mode 時這幾個與 `aws-ebs-csi-driver` 不需要。`metrics-server` 一律建議加（J6）。只有 Fargate 時，`coredns` 的 `configuration_values` 要設 Fargate 的 compute type（key 大小寫未確認）。
- 存取：
  - `access_entries = map(object({ principal_arn, type = "STANDARD", policies = map(object({ policy = "AmazonEKSClusterAdminPolicy" 等名稱, namespaces = [] })) }))`。`namespaces` 空的時候是 cluster scope。至少一個 cluster scope 的 `AmazonEKSClusterAdminPolicy`（J3）。
  - `pod_identity_associations = map(object({ namespace, service_account, role_arn }))`。
- `tags`。

主要輸出：`cluster_name`、`cluster_arn`、`endpoint`、`certificate_authority_data`、`oidc_issuer_url`（給 `iam-oidc-provider`）、`cluster_security_group_id`、`node_group_names`、`karpenter_interruption_queue_name`（沒開時 null）、`log_group_name`。

CI 用 Helm 部署的最小權限（寫進 README，範例放在 `examples/`）：

- 為 CI 的 deploy role 建 `STANDARD` access entry，關聯 namespace scope 的 `AmazonEKSEditPolicy`。Edit 含 Secret 的讀寫，Helm 的 release 紀錄存在 Secret 裡，所以夠用。
- chart 會建 Role 或 RoleBinding 時，改用 namespace scope 的 `AmazonEKSAdminPolicy`；Edit 不含 roles 與 rolebindings。
- CRD 與 cluster scope 的資源，CI 都裝不了，要由 `eks-addons` 或平台管理者裝。
- IAM 端只要給 `eks:DescribeCluster`。
- Edit 含 serviceaccount 的 `impersonate`，README 要註明這個風險。

tests：

- 固定值：`bootstrap_self_managed_addons = false`、`authentication_mode = "API"`、`bootstrap_cluster_creator_admin_permissions = false`、secrets 加密。
- 模式互斥（J2）的每條 validation 正反各一。
- Auto Mode：三個設定一起開；沒有 `vpc-cni` 等 add-on 也能通過。
- 非 Auto Mode 少了必要的 add-on 被拒。
- 沒有 cluster admin 的 access entry 被拒；`endpoint_public_access = true` 但沒給 CIDR 或給 `0.0.0.0/0` 被拒。
- launch template 的 IMDSv2 與 EBS 加密；`karpenter` 有值時建 SQS、5 條規則與 `EC2_LINUX` entry。

**`eks-addons`**

- `versions.tf`：`helm >= 3.0, < 4.0`（helm provider v3 把 `set` 改成 list、`kubernetes` 改成 nested object，§8）。不需要 aws provider。
- provider 由呼叫端設定。README 建議用 `exec` 跑 `aws eks get-token`，不要用 `aws_eks_cluster_auth` 的 token（15 分鐘就過期，apply 久一點會失敗），也不要 `exec` 與 `token` 混用。
- 主要輸入（物件為 null 就不裝，不用 `install_xxx` 開關，J2 同一條原則）：
  - `cluster_name`、`region`、`vpc_id`（LB Controller 在 hop limit 1 時拿不到 IMDS，要明確給，§8）。
  - `load_balancer_controller = object({ chart_version = "3.6.0", service_account = "aws-load-balancer-controller", replica_count = 2, values = {} })`，預設 null。Auto Mode 已經內建 ALB 與 NLB 的處理，兩者同時用時要用 IngressClass 的 controller 區分（README）。
  - `karpenter = object({ chart_version = "1.15.0", interruption_queue_name, default_node_class = optional(object({ node_role_name, subnet_discovery_tag, security_group_discovery_tag, ami_alias = "al2023@latest" }), {}), default_node_pool = optional(object({ cpu_limit = 100, capacity_types = ["on-demand"] }), {}) })`，預設 null。`default_node_class` 或 `default_node_pool` 設成 null 就不裝（D13）。EC2NodeClass 固定 IMDSv2 hop limit 1 與 EBS 加密。`ami_alias` 的寫法實作時核對（未確認）。
  - `argo_rollouts = object({ chart_version = "2.43.8", values = {} })`，預設 null。用 CloudWatch analysis 時需要 `cloudwatch:GetMetricData`，role 與 Pod Identity association 在 `eks-cluster`。
  - `app_namespaces = map(object({ labels = {} }))`，預設 `{}`。CI 的 Edit 權限不能建 namespace，所以由這裡先建。
  - `chart_repository_overrides = map(string)`：private cluster 指向 ECR 的 mirror。
- 本地 chart 放在 `modules/eks-addons/charts/`：`karpenter-defaults`（NodePool 與 EC2NodeClass）、`app-namespaces`。
- 主要輸出：每個 release 的 `name`、`namespace`、`version`。
- tests：`mock_provider "helm"`；物件為 null 時沒有 release；chart 版本預設值；Karpenter 的 `settings.clusterName` 與 `settings.interruptionQueue` 有傳；`default_node_pool = null` 時不裝本地 chart；`region`、`vpc_id` 有傳給 LB Controller。

### 4.3 `validate.sh` 與 CI 需要的改動

- S4-a 的允許清單加上 `modules/iam-oidc-provider/`，只准 `aws_iam_openid_connect_provider`。
- S1 改成：每個 `*.tftest.hcl` 要為 module `required_providers` 裡的每個 provider 宣告 `mock_provider`。`eks-addons` 只有 helm，所以只需要 `mock_provider "helm"`；不用 aws 的 module 宣告 `mock_provider "aws"` 會不會報錯，實作時確認（未確認）。
- 清環境變數的地方加上 `KUBECONFIG`、`KUBE_*`、`HELM_*`，跟目前清 `AWS_*` 同一個理由：漏寫 mock 的測試要失敗，不能連到本機的叢集。
- 本地 chart：有裝 `helm` 時加跑 `helm lint` 與 `helm template`，沒裝就跳過（跟 `shellcheck` 同一套做法）。CI 不另外裝 helm。
- `lb-traffic-breaker/lambda/`：有 `python3` 就跑 `python3 -m unittest`（只用標準函式庫，J15）。
- CI 的 plugin cache key 用 `versions.tf` 的雜湊，新增 helm provider 會自然換 key，不用改。
- 範本以後引用 helm provider 時，lock 檔一樣要有 darwin 與 linux 兩個 `h1:`（S10），從已經有兩個 `h1:` 的 lock 複製。

### 4.4 發版與 HCP 登記

- `release-please-config.json` 的 `packages` 加 8 個新 module；`.release-please-manifest.json` 加 8 個 `"0.1.0"`。
- 新 module 照 v0.1.1 的先例：manifest 登記 `0.1.0`，第一個 tag 手動打，之後才交給 release-please。打 tag 前先把 CHANGELOG 的「（未發布）」改成日期。
- 擴充的 3 個 module 走 release-please：2026-10-21 起 push 到 `main` 就會跑，`feat(<module>)` 的 commit 合併後會開 release PR。release PR 用 `GITHUB_TOKEN` 開，不會觸發 CI，合併前要人看 diff。
- 一次最多 push 3 個 tag（GitHub 超過 3 個不發 webhook，HCP 收不到）。8 個新 tag 分 3 批推。
- 照 [`hcp-registry-setup.md`](../../guides/hcp-registry-setup.md) §3 登記 8 個新 module，§4 的暫存目錄確認 40 個都抓得到。
- `README.md` 的 module 表加 8 列，新增「EKS」分類，`共 32 個 module` 改成 40。
- 打 tag、push、建 Release、HCP 登記之前先問使用者。

## 5. 範本整合（這次不做）

之後要做 EKS 範本時，建議的 stack 拆法與 apply 順序：

1. `network`：VPC（subnet 依 tier 加 §4.1 的 tag）、security group、VPC endpoint。private cluster 沒有 NAT 時要有 `ecr.api`、`ecr.dkr`、`s3`（gateway）、`ec2`、`sts`、`eks`、`eks-auth`、`elasticloadbalancing`、`logs`，用 Karpenter 再加 `sqs`、`ssm`（§8）。
2. `iam`：cluster role、node role、Fargate pod execution role、各 controller 的 Pod Identity role、斷路器 Lambda 的 role，全部用 `iam-role`；controller 的 policy 內容取自 `eks-iam-policies` 的輸出。
3. `eks-cluster`：叢集、節點、add-on、access entry、Pod Identity association、Karpenter 的 SQS 與 EventBridge。要 IRSA 時同一個 stack 再呼叫 `iam-oidc-provider`，IRSA 的 role 放在下一個 stack（要等 OIDC provider 的 ARN）。
4. `eks-addons`：獨立的 state 與 helm provider 設定。
5. `loadbalancer`：模式 T 的 `alb` 或 `nlb`（含加權規則）、`lambda-function`（斷路器）、`lb-traffic-breaker`。target group ARN 經 SSM 發布，給應用程式 chart 裡的 TargetGroupBinding 用。
6. 應用程式：使用者或 CI 用 Helm 部署到 `app_namespaces` 建好的 namespace，權限來自 namespace scope 的 access entry。

模式 K 不需要第 5 步的 `loadbalancer`，ALB 或 NLB 由 LB Controller 依 Ingress 或 Service 建。

斷路器觸發後的 runbook（範本 README 要寫）：

1. SNS 通知到人，確認 Lambda 已經把權重改成舊系統 100%（listener 或 rule 上有 `traffic-breaker/tripped` tag）。
2. 先把 tfvars 裡那條規則的權重改成舊系統 100%、新系統 0，再 apply。這一步沒做，下次任何人 apply 都會把新系統的權重改回來（R1）。
3. 修好新系統後，照正常流程逐步調回權重，每一步都是改 tfvars 再 apply。
4. 確認 alarm 回到 OK，再移除 tag。

## 6. mock 驗不到、要真實環境才能確認的推論

- ALB 新系統 target group 全掛時，fail open 加上不自動 failover，使用者會直接看到錯誤，直到 Lambda 改完權重。實際從 alarm 到權重生效要多久，要量測。
- NLB 改權重後最多約 3 分鐘才生效、只影響新連線（AWS blog 的說法）。
- NLB 多個 target group 時把 `dns_failover` 設成 `"off"`，能不能避免整個 zone 被移出 DNS。
- NLB 的 security group 只能在建立時加。
- NLB 的 stickiness 會不會用到 `duration`（provider 必填，NLB 文件沒寫）。
- Pod Identity association 能不能在 namespace 與 service account 還不存在時先建。
- LB Controller v3.6.0 用 Pod Identity（安裝文件同時寫「Pod Identity 推薦」與「best practice 是 IRSA」）。
- LB Controller 透過 TargetGroupBinding 註冊 Pod 到 Terraform 建的 target group 時，官方 IAM policy 是否已涵蓋（`RegisterTargets` 有沒有 tag 條件）。TargetGroupBinding 的 `networking` 區段會不會去改 Terraform 管的 SG 規則。
- Argo Rollouts 用 Pod Identity 讀 CloudWatch（文件只提到 IRSA 與 access key，AWS SDK 的預設憑證鏈理論上支援）。
- Argo Rollouts 的 CloudWatch analysis 要用 LB Controller 產生的 target group 名稱當維度，怎麼在 AnalysisTemplate 裡拿到。
- Auto Mode 與 zonal shift。
- `coredns` add-on 跑在 Fargate 的 `configuration_values` key。
- Karpenter EC2NodeClass 的 `amiSelectorTerms` alias 寫法。
- `AmazonEBSCSIDriverPolicyV2`、`AmazonEKSBlockStoragePolicyV2` 等 managed policy 的實際 ARN 路徑。
- 斷路器 Lambda 被 alarm 呼叫時的 event 格式與重試行為。

## 7. 風險

| # | 風險 | 處理 |
|---|---|---|
| R1 | 斷路器改了權重之後，下次 apply 會被 Terraform 改回 tfvars 的值，新系統又接到流量 | Lambda 在 listener 或 rule 加 `traffic-breaker/tripped` tag；runbook 規定先改 tfvars 再 apply（§5）；README 寫明 apply 前看 plan 有沒有改權重 |
| R2 | 模式 K 的規則被人接上 A'，Lambda 改的權重會被 LB Controller 改回去，斷路器形同無效 | `lb-traffic-breaker` 的 README 寫明只能用在 Terraform 擁有的 listener 與 rule；Lambda 只碰 `breakers` 列出的 ARN |
| R3 | Fargate 用 IRSA，跟其他地方的 Pod Identity 並存，權限審查要看兩套 | IRSA 只限 Fargate；`iam-role` 的 `federated` 要求 `subject` 指到單一 service account |
| R4 | `support_type = "EXTENDED"` 過了 standard 期會另外計費，使用者可能沒注意 | `eks-cluster` 的 README 與 variable description 寫明；範本 tfvars 加註解 |
| R5 | LB Controller 的官方 IAM policy 很長，放進 `iam-role` 的 inline policy 可能超過單一 role 的 inline policy 總長度上限（未確認實際長度） | `eks-iam-policies` 實作時量測並寫進 README；超過就拆成 `iam-role-policy` 的多份 policy |
| R6 | NLB 的新系統 target group 在某個 AZ 沒有健康 target，整個 zone 被移出 DNS，舊系統流量也受影響 | J12 的 validation；README 寫明每個 AZ 都要有新系統的 target |
| R7 | NLB 切回舊系統只影響新連線，長連線會一直留在新系統 | README 寫明；需要即時切斷時在 NLB 後面接 ALB 做 L7 權重（target type `alb`），列為已知限制 |
| R8 | `bootstrap_cluster_creator_admin_permissions = false` 但沒有 admin access entry，apply 完就沒有人能操作叢集 | J3 的 validation |
| R9 | `bootstrap_self_managed_addons`、`encryption_config`、Auto Mode 的 `node_role_arn` 都是 ForceNew，改錯會重建叢集 | 前兩個固定值、不提供開關；`deletion_protection = true` 預設開；README 列出會 ForceNew 的輸入 |
| R10 | helm provider 是 repo 第一個非 aws 的主要 provider，S1、mock、lock 檔的規則都要改 | §4.3；A0 先改 `validate.sh` 再寫 module |
| R11 | Lambda 失敗時權重沒改到，alarm 仍是 ALARM 不會再觸發 | alarm 同時送 SNS 給人；Lambda 寫自己的錯誤 log，`lambda-function` 的 log group 照常保留 |
| R12 | 斷路器 Lambda 的映像由使用者自己 build，版本可能跟 module 不一致 | README 寫明映像 tag 要跟 module 版本對齊；`BREAKER_CONFIG` 帶 schema 版本，Lambda 遇到不認得的版本就失敗並記 log |
| R13 | Auto Mode 與 Fargate 能不能長期共存未確認，module 不擋（D17） | `eks-cluster` 的 README 寫明官方沒有說能長期共存；真實環境遇到問題再補 validation（MINOR） |

## 8. 來源

ALB、NLB、斷路器：

- ALB listener rules：https://docs.aws.amazon.com/elasticloadbalancing/latest/application/listener-rules.html
- ALB 健康檢查與 fail open：https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html
- ALB 加權 target group 與 stickiness：https://docs.aws.amazon.com/elasticloadbalancing/latest/application/rule-action-types.html
- ALB quotas：https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-limits.html
- ALB target group health（`unhealthy_state_routing`、`dns_failover`）：https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html
- ALB 指標：https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-cloudwatch-metrics.html
- NLB listener 與加權 target group：https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-listeners.html
- NLB 加權 target group 上線公告：https://aws.amazon.com/about-aws/whats-new/2025/11/network-load-balancer-weighted-target-groups/
- NLB 加權 target group blog（生效時間）：https://aws.amazon.com/blogs/networking-and-content-delivery/network-load-balancers-now-support-weighted-target-groups/
- NLB quotas：https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-limits.html
- NLB 健康檢查與 DNS failover：https://docs.aws.amazon.com/elasticloadbalancing/latest/network/target-group-health-checks.html
- NLB 指標：https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html
- `ModifyListener` 要帶完整清單：https://docs.aws.amazon.com/elasticloadbalancing/latest/APIReference/API_ModifyListener.html
- alarm 呼叫 Lambda：https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/alarms-and-actions-Lambda.html
- alarm 與 missing data：https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/alarms-and-missing-data.html
- alarm 與 EventBridge：https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch-and-eventbridge.html

AWS Load Balancer Controller 與 Argo Rollouts：

- 安裝與 Pod Identity：https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v3.6.0/docs/deploy/installation.md
- IAM policy：https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.6.0/docs/install/iam_policy.json
- reconcile 與 out-of-band 修改：同 repo 的 `docs/how-it-works.md`、`docs/deploy/configurations.md`
- subnet tag：https://docs.aws.amazon.com/eks/latest/userguide/network-load-balancing.html
- Helm chart：`https://aws.github.io/eks-charts` 的 `aws-load-balancer-controller` 3.6.0
- Argo Rollouts ALB：https://github.com/argoproj/argo-rollouts/blob/v1.10.1/docs/features/traffic-management/alb.md
- Argo Rollouts CloudWatch analysis：https://github.com/argoproj/argo-rollouts/blob/v1.10.1/docs/analysis/cloudwatch.md
- Argo Rollouts Gateway API plugin：https://github.com/argoproj-labs/rollouts-plugin-trafficrouter-gatewayapi
- Helm chart：`https://argoproj.github.io/argo-helm` 的 `argo-rollouts` 2.43.8

EKS：

- Kubernetes 版本：https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
- IAM best practice（creator admin、IMDS hop limit、token TTL）：https://docs.aws.amazon.com/eks/latest/best-practices/identity-and-access-management.html
- Auto Mode 建立與 IAM：https://docs.aws.amazon.com/eks/latest/userguide/create-cluster-auto.html 、https://docs.aws.amazon.com/eks/latest/userguide/auto-learn-iam.html
- Auto Mode FAQ 與遷移：https://docs.aws.amazon.com/eks/latest/best-practices/automode.html 、https://docs.aws.amazon.com/eks/latest/userguide/auto-migrate-karpenter.html 、https://docs.aws.amazon.com/eks/latest/userguide/migrate-auto.html
- access policy：https://docs.aws.amazon.com/eks/latest/userguide/access-policy-permissions.html 、https://docs.aws.amazon.com/eks/latest/userguide/creating-access-entries.html
- launch template：https://docs.aws.amazon.com/eks/latest/userguide/launch-templates.html
- AL2 停止支援：https://docs.aws.amazon.com/eks/latest/userguide/eks-ami-deprecation-faqs.html
- Fargate：https://docs.aws.amazon.com/eks/latest/userguide/fargate.html 、https://docs.aws.amazon.com/eks/latest/userguide/pod-execution-role.html
- Pod Identity：https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html
- add-on：https://docs.aws.amazon.com/eks/latest/userguide/workloads-add-ons-available-eks.html 、https://docs.aws.amazon.com/eks/latest/userguide/community-addons.html
- control plane log：https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html
- private cluster 的 VPC endpoint：https://docs.aws.amazon.com/eks/latest/userguide/private-clusters.html
- Karpenter IAM 與事件：https://karpenter.sh/docs/reference/cloudformation/ ；chart `oci://public.ecr.aws/karpenter/karpenter` 1.15.0
- provider：aws 6.69.1、helm 3.3.0、kubernetes 3.4.0 的 schema（`terraform providers schema -json`）；helm provider 的 `docs/guides/v3-upgrade-guide.md`；kubernetes provider 文件對同一次 apply 的警告
