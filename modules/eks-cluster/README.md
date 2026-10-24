# eks-cluster

一個 EKS 叢集的 AWS 資源：叢集本身、control plane log group、節點（managed node group、Fargate profile、Auto Mode，或 Karpenter 要用的 SQS 與 EventBridge）、add-on、access entry、Pod Identity association。叢集裡面的東西（Helm chart、CRD）不在這裡，由另一個 stack 的 `eks-addons` 裝（兩次 apply，叢集在前）。

這個 module 不建任何 IAM role 與 security group：cluster role、node role、Fargate pod execution role、Karpenter controller role、Pod Identity role 都由呼叫端用 `iam-role` 建好，module 只收 ARN。也不讀 SSM 參數。

## 用法

```hcl
module "eks" {
  source = "git::https://github.com/<org>/<repo>.git//modules/eks-cluster?ref=eks-cluster-v0.1.0"

  name               = "alpha-dev"
  kubernetes_version = "1.34"
  subnet_ids         = module.vpc.private_subnet_ids
  kms_key_arn        = module.eks_kms.arn
  cluster_role_arn   = module.eks_cluster_role.arn

  managed_node_groups = {
    system = {
      node_role_arn  = module.eks_node_role.arn
      instance_types = ["m7i.large"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
    }
  }

  addons = {
    vpc-cni                = { version = "v1.20.0-eksbuild.1" }
    kube-proxy             = { version = "v1.34.0-eksbuild.1" }
    coredns                = { version = "v1.12.0-eksbuild.1" }
    eks-pod-identity-agent = { version = "v1.3.0-eksbuild.1" }
  }

  access_entries = {
    platform = {
      principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
      policies = {
        admin = { policy = "AmazonEKSClusterAdminPolicy" }
      }
    }
  }

  tags = {
    Project = "alpha"
  }
}
```

範例（都放在 `examples/`，用佔位 ARN）：

| 範例 | 內容 |
|---|---|
| [`examples/mng-karpenter/`](./examples/mng-karpenter/main.tf) | managed node group 跑系統元件，Karpenter 開其他節點；含 EBS CSI 的 Pod Identity、CI 的 namespace 權限 |
| [`examples/auto-mode/`](./examples/auto-mode/main.tf) | Auto Mode，只裝 `metrics-server` |
| [`examples/mng-fargate/`](./examples/mng-fargate/main.tf) | managed node group 加 Fargate profile |

## 四種節點模式與互斥規則

模式由輸入決定，沒有 `enable_xxx`。`managed_node_groups`、`fargate_profiles` 是 map，空的就不建；`auto_mode`、`karpenter` 是物件，`null` 就不建。

| 輸入 | 建什麼 |
|---|---|
| `managed_node_groups` | 每個 group 一個 launch template 加一個 node group |
| `fargate_profiles` | 每個 profile 一個 Fargate profile |
| `auto_mode` | 打開 Auto Mode 的 compute、負載平衡、區塊儲存 |
| `karpenter` | interruption 用的 SQS queue、5 條 EventBridge 規則、node role 的 `EC2_LINUX` access entry、controller 的 Pod Identity association |

規則：

- 四種至少要有一種，否則 plan 失敗（`aws_eks_cluster.this` 的 precondition。這條跨四個變數，寫成變數的 validation 會互相循環參照，所以放在資源上）。
- `auto_mode` 與 `karpenter` 互斥，兩者共用 `nodepools.karpenter.sh`、`nodeclaims.karpenter.sh` 這兩個 CRD。
- `karpenter` 要至少一個 managed node group 來跑 controller。
- `karpenter.node_role_arn` 不能跟任何 managed node group 的 `node_role_arn` 相同。EKS 會替 managed node group、Fargate profile、Auto Mode 的 node role 自動建 access entry，同一個 principal 再建一次會被擋（依 EKS 行為推得，沒在真實環境驗證過）。Karpenter 的節點請用另一個 role。
- 其他組合都可以：managed node group 加 Fargate、managed node group 加 Auto Mode、Auto Mode 加 Fargate。

### Auto Mode 的三個設定

`auto_mode` 有值時，`compute_config.enabled`、`kubernetes_network_config.elastic_load_balancing.enabled`、`storage_config.block_storage.enabled` 三個一起設成 `true`，`compute_config` 帶 `node_role_arn` 與 `node_pools`（預設 `general-purpose`、`system`）。

`auto_mode = null` 時三個明確送 `false`，不是不送。原因：provider 規定三者要同開或同關，要關閉 Auto Mode 也必須三個都送 `false`；不送的話，把 `auto_mode` 從有值改回 `null` 就不會關掉 Auto Mode。建立新叢集時，provider 本來就會對沒設定的項目補 `enabled = false`（`aws_eks_cluster` 的 `expandKubernetesNetworkConfigRequest` 註解），所以這樣做對新叢集沒有差別。

`node_role_arn` 設定後再換成另一個 role 會重建叢集（見〈會 ForceNew 的輸入〉）。

Auto Mode 的叢集，cluster role 的 trust 要有 `sts:TagSession`（`iam-role` 的 `trust.tag_session = true`）。

### Auto Mode 不帶內建 node pool（AWS 的標準做法）

使用者自己用 NodeClass、NodePool 管節點時，叢集建立時不需要內建 node pool，也不需要 node role：

```hcl
auto_mode = {
  node_pools = []   # node_role_arn 省略（null）
}

access_entries = {
  # ...cluster admin entry...
  auto_nodes = {
    principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-auto-node"
    type          = "EC2"
    policies = {
      node = { policy = "AmazonEKSAutoNodePolicy" }
    }
  }
}
```

- `node_role_arn` 只有在 `node_pools = []` 時才能是 `null`；`node_pools` 有值卻沒給 role，plan 失敗。有給 role 時行為跟以前一樣。
- `node_pools = []` 時，`access_entries` 必須有一個 `type = "EC2"` 的 entry 掛 `AmazonEKSAutoNodePolicy`，否則 plan 失敗（`aws_eks_cluster.this` 的 precondition），因為沒有它 Auto Mode 的節點無法加入叢集。node role 本身由呼叫端建（`iam-role`），NodeClass 的 `role` 指向它。

## add-on

`addons` 的 key 是 add-on 名稱，`version` 必填（版本跟 `kubernetes_version` 綁在一起，module 不給預設）。

- 沒有 `auto_mode` 時，`vpc-cni`、`kube-proxy`、`coredns`、`eks-pod-identity-agent` 必須在 `addons` 裡。叢集固定用 `bootstrap_self_managed_addons = false` 建，不會自帶這幾個，少了就沒有網路與 DNS。
- 有 `auto_mode` 時這四個（與 EBS CSI driver）不需要，Auto Mode 已經內建。`metrics-server` 不論哪種模式都建議加（EKS 的 community add-on，不用 Helm）。
- `pod_identity_role_arn` 與 `service_account` 要一起給，會建 add-on 的 Pod Identity association（例如 `aws-ebs-csi-driver` 的 `ebs-csi-controller-sa`）。
- `resolve_conflicts_on_update` 預設 `OVERWRITE`，可以是 `NONE`、`PRESERVE`。

建立順序：

1. `vpc-cni`、`kube-proxy`、`eks-pod-identity-agent` 先建，不用等節點（它們是 DaemonSet，沒有節點也能 ACTIVE）。
2. 節點（managed node group）等這三個建好才建，因為節點要有 CNI 才會 Ready。Fargate profile 不等。
3. 其他 add-on（`coredns`、`aws-ebs-csi-driver`、`metrics-server` 等）等節點與 Fargate profile 建好才建，不然會因為沒有節點可排程，卡在 DEGRADED。

`kube-proxy` 放在第 1 組是這個 module 的判斷（它也是 DaemonSet，社群的 `terraform-aws-eks` 也這樣排），設計文件只寫了 `vpc-cni` 與 `eks-pod-identity-agent`。只有 Fargate 時，`coredns` 的 `configuration_values` 要指定在 Fargate 上跑（`computeType` 的大小寫沒確認過，要在真實環境驗證）。

## 存取

`access_entries` 是 map：`principal_arn`、`type`（預設 `STANDARD`，也可以是 `EC2`、`EC2_LINUX`、`EC2_WINDOWS`、`FARGATE_LINUX`）、`policies`（map：`policy` 與 `namespaces`）。`namespaces` 空的是 cluster scope，有值是 namespace scope。

- 叢集固定用 `authentication_mode = "API"` 與 `bootstrap_cluster_creator_admin_permissions = false`，建立叢集的人不會自動變成 admin。所以 `access_entries` 至少要有一個 `STANDARD` entry 帶 cluster scope 的 `AmazonEKSClusterAdminPolicy`（給跑 `terraform apply` 的 role），不然 plan 失敗，因為沒有它 apply 完之後沒有人能操作叢集。
- `policy` 只收名稱，白名單：`AmazonEKSClusterAdminPolicy`、`AmazonEKSAdminPolicy`、`AmazonEKSEditPolicy`、`AmazonEKSViewPolicy`、`AmazonEKSAdminViewPolicy`。module 組成 `arn:aws:eks::aws:cluster-access-policy/<名稱>`（partition 固定 `aws`）。
- 只有 `STANDARD` 與 `EC2` 的 entry 能掛 policy。`STANDARD` 只能掛上面五個；`EC2`（Auto Mode 的 node role 用）只能掛 `AmazonEKSAutoNodePolicy`，而且只能是 cluster scope（`namespaces` 空的）；`AmazonEKSAutoNodePolicy` 不能掛在其他 type。`EC2` 與 `EC2_LINUX` 是不同的 type，只有 `EC2` 能關聯 access policy。
- `pod_identity_associations` 是 map：`namespace`、`service_account`、`role_arn`。role 的 trust 要是 `pods.eks.amazonaws.com` 並帶 `sts:TagSession`。

## CI 用 Helm 部署的最小權限

CI 的 deploy role 只需要這些：

- IAM 端只給 `eks:DescribeCluster`（`aws eks update-kubeconfig` 用）。
- 建一個 `STANDARD` access entry，關聯 namespace scope 的 `AmazonEKSEditPolicy`（`namespaces = ["apps"]`）。Edit 含 Secret 的讀寫，Helm 的 release 紀錄存在 Secret 裡，所以夠用。
- chart 會建 Role 或 RoleBinding 時，改用 namespace scope 的 `AmazonEKSAdminPolicy`。Edit 不含 `roles` 與 `rolebindings`。
- CRD 與 cluster scope 的資源（`ClusterRole`、`Namespace` 等）CI 都裝不了，要由 `eks-addons` 或平台管理者裝。namespace 也要先建好，`eks-addons` 的 `app_namespaces` 可以做。
- **風險**：Edit 含 `serviceaccounts` 的 `impersonate`，能 impersonate 同 namespace 的 service account，拿到那個 service account 的權限（包含它的 Pod Identity 或 IRSA role）。CI 能部署的 namespace 就是它的權限邊界，不要把 Edit 開在放高權限 workload 的 namespace。

```hcl
access_entries = {
  ci = {
    principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-ci-deploy"
    policies = {
      apps = { policy = "AmazonEKSEditPolicy", namespaces = ["apps"] }
    }
  }
}
```

## 會 ForceNew 的輸入（R9）

改了就會刪掉重建叢集，所有節點與叢集內的東西都沒了。`deletion_protection` 預設 `true`，要重建（或 destroy）得先改成 `false` 並 apply 一次。

| 輸入 | 說明 |
|---|---|
| `name` | 叢集名稱 |
| `cluster_role_arn` | provider 標 ForceNew |
| `bootstrap_self_managed_addons`、`access_config.bootstrap_cluster_creator_admin_permissions` | module 固定，沒有輸入。已經用其他值建出來的叢集，接進這個 module 會被判定要重建 |
| `kms_key_arn`（`encryption_config`） | 加密開了就不能關，移除會重建。換成另一把 key 在 provider 沒標 ForceNew，AWS 是否允許未確認 |
| `auto_mode.node_role_arn` | 設定後換成另一個 role 會重建（provider 的 CustomizeDiff）。從 `null` 變有值、或關閉 Auto Mode 不會 |

另外 `managed_node_groups`、`fargate_profiles`、`addons`、`access_entries` 的 map key 改名，等於刪掉舊的、建新的。

## support_type 與計費（R4）

`support_type` 預設 `EXTENDED`（D10，也是 AWS 的預設）。版本過了 standard support 之後會進 extended support，**每個叢集每小時另外計費**，金額以 AWS 當下的 EKS 定價頁為準。好處是不會被逼著升級。

不想額外付費就設 `support_type = "STANDARD"`：到 standard support 結束時 AWS 會自動把叢集升到下一個版本。兩種都要規劃升級；標準期限看 AWS 的 Kubernetes versions 頁面。

## Auto Mode 加 Fargate（D17、R13）

`auto_mode` 與 `fargate_profiles` 可以同時設，module 不擋。**官方文件沒有說 Auto Mode 與 Fargate 能不能長期並存**，風險自負；真實環境遇到問題再補 validation。Auto Mode 與 managed node group 並存，官方 FAQ 有寫可以。Auto Mode 的 zonal shift 支援，兩份官方文件說法不同（未確認），`zonal_shift` 開了也不保證生效。

## Fargate 只能用 IRSA（D7）

Fargate 不支援 EKS Pod Identity，也不支援 DaemonSet、privileged、HostNetwork、EBS、Fargate Spot。Fargate 上的 Pod 要存取 AWS，只能用 IRSA：用 `iam-oidc-provider`（輸入是這個 module 的 `oidc_issuer_url`）加 `iam-role` 的 `federated` trust。其他地方一律用 Pod Identity。Fargate profile 的 subnet 只能是 private。

## 注意

- **kubernetes_version 必填。** 不給預設，因為版本跟 add-on 版本綁在一起。升級是改這個值，只能往上。
- **control plane log group 由 module 先建。** `/aws/eks/<name>/cluster`，保留天數預設 30、不接受 0（永不過期），可以指定 KMS key（key policy 要允許 `logs.<region>.amazonaws.com`）。叢集 `depends_on` 它，不然 EKS 會自己建一個永不過期的。已經有同名 log group 的環境要先 `terraform import`。`enabled_log_types` 預設 `api`、`audit`、`authenticator`。
- **API endpoint 預設只開 private。** `endpoint_public_access = true` 時 `public_access_cidrs` 必填，不接受 `0.0.0.0/0` 與 `::/0`、也不接受格式錯的 CIDR。public 關著時 `public_access_cidrs` 被忽略。
- **launch template 固定的安全設定，沒有開關**：IMDSv2 必須、hop limit 1（Pod 拿不到 node role，要 AWS 權限走 Pod Identity）、root volume 是加密的 gp3（`disk_size` 預設 50、最小 20；`disk_kms_key_arn` 空的用帳號預設 EBS key）。
- **只支援 AL2023 的 `ami_type`**（`AL2023_x86_64_STANDARD`、`AL2023_ARM_64_STANDARD`、`AL2023_x86_64_NEURON`、`AL2023_x86_64_NVIDIA`）。AL2 已經不再發布；Bottlerocket 的資料碟是 `/dev/xvdb`，跟 module 加密的 `/dev/xvda` 對不上，所以沒放進白名單。要用 Bottlerocket 的節點請用 Auto Mode。
- **`desired_size` 只在建立時用。** 之後被 `ignore_changes` 忽略，數量交給 autoscaler。要改常態數量請改 `min_size`、`max_size`。
- **launch template 改了會滾動更新節點。** node group 帶的是 launch template 的版本號，不是 `$Latest`。更新速度由 `max_unavailable_percentage`（預設 33）控制。
- **Karpenter queue 用叢集名稱當名稱**，跟 Karpenter 官方 CloudFormation 一致。EventBridge 規則名稱是 `<name>-karpenter-<health|spot|rebalance|state|capacity>`，所以 `name` 最長 40 個字元。
- **Karpenter queue policy 比官方窄一點。** 官方的 policy 讓任何 EventBridge 規則都能送訊息，這裡的 `events.amazonaws.com` 加了 `aws:SourceArn` 條件，只准這個 module 的 5 條規則，避免別的帳號對 queue 送假的中斷事件。`sqs.amazonaws.com` 與拒絕非 TLS 的 statement 跟官方一樣。
- **Karpenter 的 5 條規則** 的 event pattern 取自 Karpenter v1.15.0 的 `cloudformation.yaml`（`website/content/en/docs/getting-started/getting-started-with-karpenter/cloudformation.yaml`）：AWS Health Event、EC2 Spot Instance Interruption Warning、EC2 Instance Rebalance Recommendation、EC2 Instance State-change Notification、EC2 Capacity Reservation Instance Interruption Warning。Karpenter 的 controller IAM policy 在 `eks-iam-policies`，EC2NodeClass 與 NodePool 在 `eks-addons`。
- private cluster（沒有 NAT）需要的 VPC endpoint 見設計文件 §5，Karpenter 另外要 `sqs`、`ssm`。
- partition 在 access policy ARN 固定是 `aws`。
- **module 沒辦法在離線測試中驗證的事**（設計文件 §6）：Pod Identity association 能不能在 namespace 與 service account 還不存在時先建、Auto Mode 與 zonal shift、`coredns` 在 Fargate 的 `configuration_values`。

## 刻意不做

- IAM role、instance profile、OIDC provider（用 `iam-role`、`iam-oidc-provider` 建）、security group（用 `security-group` 建）。
- 讀 SSM 參數。
- 開關：`bootstrap_self_managed_addons`、`authentication_mode`、`bootstrap_cluster_creator_admin_permissions` 固定值，沒有輸入（三個都是 ForceNew）。
- 自管節點（self-managed node group）、Bottlerocket 的 managed node group、Outposts、EKS Hybrid Nodes、IPv6、自訂 service CIDR、provisioned control plane。
- node group 的 SSH key（`remote_access`）、warm pool、node repair 設定。
- Helm chart 與叢集內的任何資源（用 `eks-addons`）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | 叢集名稱，也是 node group launch template、Karpenter queue 與 EventBridge 規則名稱的前綴，所以上限 40 字元。2–40 字元，小寫字母開頭，限小寫英數字與連字號。 |
| `kubernetes_version` | `string` | 無 | 是 | Kubernetes minor 版本，例如 `1.34`。必填、沒有預設，因為版本跟 add-on 版本綁在一起。 |
| `support_type` | `string` | `"EXTENDED"` | 否 | 升級政策的 support type：`STANDARD` 或 `EXTENDED`。`EXTENDED`（AWS 預設）在版本過了 standard support 後另外計費；`STANDARD` 會在 standard support 結束時自動升級叢集。 |
| `subnet_ids` | `list(string)` | 無 | 是 | control plane 網路介面用的 subnet，至少兩個，要在不同 AZ，格式像 `subnet-0123456789abcdef0`。managed node group 沒給 subnet 時也用這些。 |
| `security_group_ids` | `list(string)` | `[]` | 否 | control plane 網路介面額外的 security group，格式像 `sg-0123456789abcdef0`。cluster security group 一律由 EKS 自己建。 |
| `endpoint_public_access` | `bool` | `false` | 否 | API server endpoint 是否開放從網際網路連線。private endpoint 一律開。 |
| `public_access_cidrs` | `list(string)` | `[]` | 否 | 可以連 public endpoint 的 CIDR。`endpoint_public_access` 為 `true` 時必填，須是合法 CIDR，不接受 `0.0.0.0/0` 與 `::/0`。public endpoint 關著時忽略。 |
| `kms_key_arn` | `string` | 無 | 是 | Kubernetes secrets envelope encryption 用的客戶自管 KMS key ARN，不接受 alias。必填。加密開了之後不能關，移除會重建叢集。 |
| `cluster_role_arn` | `string` | 無 | 是 | 叢集的 IAM role ARN，由呼叫端用 `iam-role` 建。 |
| `enabled_log_types` | `list(string)` | `[ "api", "audit", "authenticator" ]` | 否 | 送到 module 建的 log group 的 control plane log 類型，可選 `api`、`audit`、`authenticator`、`controllerManager`、`scheduler`。 |
| `log_retention_days` | `number` | `30` | 否 | control plane log group 的保留天數，須是 CloudWatch Logs 接受的值（1、3、5、7、14、30、60、90 … 3653）。不接受永不過期（`0`）。 |
| `log_kms_key_arn` | `string` | `null` | 否 | control plane log group 用的客戶自管 KMS key ARN，不接受 alias；key policy 要允許 `logs.<region>.amazonaws.com`。`null` 時不指定 KMS key。 |
| `deletion_protection` | `bool` | `true` | 否 | 開著時叢集不能刪除；要刪除或重建，先改成 `false` 並 apply 一次。 |
| `zonal_shift` | `bool` | `false` | 否 | 是否開啟叢集的 ARC zonal shift。 |
| `managed_node_groups` | `map(object)` | `{}` | 否 | managed node group，key 是 group 名稱（1–63 字元，小寫英數字與連字號）；空 map 不建。module 替每個 group 建一個 launch template（IMDSv2 必須、hop limit 1、加密的 gp3 root volume）。欄位見〈`managed_node_groups` 欄位〉。 |
| `fargate_profiles` | `map(object)` | `{}` | 否 | Fargate profile，key 是 profile 名稱（1–63 字元，小寫英數字與連字號）；空 map 不建。欄位：`pod_execution_role_arn`（IAM role ARN）、`subnet_ids`（至少一個，只能是 private subnet）、`selectors`（至少一個，各有 `namespace` 與 `labels`，`labels` 預設 `{}`）。Fargate pod 不能用 EKS Pod Identity，只能用 IRSA。 |
| `auto_mode` | `object` | `null` | 否 | EKS Auto Mode；`null` 不開（三個設定明確送 `false`）。有值時 compute、負載平衡、區塊儲存三個一起開。欄位：`node_pools`（預設 `["general-purpose", "system"]`，只能是這兩個）、`node_role_arn`（IAM role ARN，`node_pools` 非空時必填，設定後換 role 會重建叢集；只有 `node_pools = []` 時可以是 `null`，此時 `access_entries` 要有 `EC2` entry 掛 `AmazonEKSAutoNodePolicy`）。 |
| `karpenter` | `object` | `null` | 否 | Karpenter 要的 AWS 資源：interruption SQS queue、5 條 EventBridge 規則、Karpenter node role 的 `EC2_LINUX` access entry、controller 的 Pod Identity association；`null` 不建。需要至少一個 managed node group 跑 controller，不能與 `auto_mode` 並用。欄位：`node_role_arn`（必填，IAM role ARN，不能跟任何 managed node group 的 node role 相同）、`controller_role_arn`（必填，IAM role ARN）、`controller_namespace`（預設 `kube-system`）、`controller_service_account`（預設 `karpenter`）。 |
| `addons` | `map(object)` | `{}` | 否 | 沒有 `auto_mode` 時必填。EKS add-on，key 是 add-on 名稱（例如 `vpc-cni`）；沒有 `auto_mode` 時必須含 `vpc-cni`、`kube-proxy`、`coredns`、`eks-pod-identity-agent`，因為叢集不帶自管 add-on。欄位：`version`（必填，跟 `kubernetes_version` 綁在一起）、`configuration_values`、`pod_identity_role_arn` 與 `service_account`（要一起給，會建 Pod Identity association）、`resolve_conflicts_on_update`（預設 `OVERWRITE`，可為 `NONE`、`PRESERVE`）。建立順序見〈add-on〉。 |
| `access_entries` | `map(object)` | 無 | 是 | EKS access entry，key 是名稱。欄位：`principal_arn`（IAM role 或 user ARN）、`type`（預設 `STANDARD`，可為 `EC2`、`EC2_LINUX`、`EC2_WINDOWS`、`FARGATE_LINUX`）、`policies`（map，每項是 `policy` 名稱與 `namespaces`，`namespaces` 預設 `[]` 代表 cluster scope）。至少要一個 `STANDARD` entry 掛 cluster scope 的 `AmazonEKSClusterAdminPolicy`；只有 `STANDARD`、`EC2` 能掛 policy，`EC2` 只能掛 cluster scope 的 `AmazonEKSAutoNodePolicy`。policy 白名單見〈存取〉。 |
| `pod_identity_associations` | `map(object)` | `{}` | 否 | EKS Pod Identity association，key 是名稱。欄位：`namespace`、`service_account`、`role_arn`（呼叫端用 `iam-role` 建的 IAM role ARN，trust 要是 `pods.eks.amazonaws.com` 並帶 `sts:TagSession`）。Fargate pod 不能用 Pod Identity。 |
| `tags` | `map(string)` | `{}` | 否 | module 建的每個資源的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `cluster_name` | 叢集名稱。 |
| `cluster_arn` | 叢集 ARN。 |
| `endpoint` | API server endpoint URL。 |
| `certificate_authority_data` | 叢集 CA（base64），給 kubeconfig 與 kubernetes、helm provider 用。 |
| `oidc_issuer_url` | 叢集的 OIDC issuer URL，`iam-oidc-provider` 的輸入。 |
| `cluster_security_group_id` | EKS 建的 cluster security group ID。 |
| `service_ipv4_cidr` | 叢集的 Kubernetes service CIDR（沒指定時 EKS 從 `10.100.0.0/16`、`172.20.0.0/16` 擇一）。 |
| `node_group_names` | managed node group 名稱的清單。 |
| `karpenter_interruption_queue_name` | Karpenter interruption SQS queue 名稱；沒開 `karpenter` 時是 `null`。 |
| `log_group_name` | control plane log group 名稱。 |
<!-- END_TF_DOCS -->

## `managed_node_groups` 欄位

`managed_node_groups` 每個 group 的欄位：

| 欄位 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `node_role_arn` | `string` | 必填 | node role 的 IAM role ARN |
| `subnet_ids` | `list(string)` | 叢集的 `subnet_ids` | 有給時不能是空清單 |
| `ami_type` | `string` | `AL2023_x86_64_STANDARD` | 可為 `AL2023_x86_64_STANDARD`、`AL2023_ARM_64_STANDARD`、`AL2023_x86_64_NEURON`、`AL2023_x86_64_NVIDIA` |
| `instance_types` | `list(string)` | 必填 | 至少一個 |
| `capacity_type` | `string` | `ON_DEMAND` | `ON_DEMAND` 或 `SPOT` |
| `min_size` | `number` | 必填 | 須滿足 `0 <= min_size <= desired_size <= max_size` |
| `max_size` | `number` | 必填 | 至少 1 |
| `desired_size` | `number` | 必填 | 只在建立時用，之後交給 autoscaler |
| `disk_size` | `number` | `50` | root volume 大小（GiB），20–16384 |
| `disk_kms_key_arn` | `string` | `null` | root volume 的 KMS key ARN，不接受 alias；`null` 用帳號預設 EBS key |
| `labels` | `map(string)` | `{}` | 節點 label |
| `taints` | `list(object)` | `[]` | 每項 `key`、`value`（選填）、`effect`（`NO_SCHEDULE`、`NO_EXECUTE`、`PREFER_NO_SCHEDULE`） |
| `max_unavailable_percentage` | `number` | `33` | 滾動更新時同時不可用的節點比例，1–100 |

## 測試

```bash
scripts/validate.sh modules/eks-cluster
```

`tests/` 依主題分檔：`cluster`（叢集設定與固定值）、`node-groups`（managed node group 與 launch template）、`node-modes`（Fargate、Auto Mode、互斥規則）、`auto-mode-nodes`（不帶 node role 與內建 node pool 的 Auto Mode、`service_ipv4_cidr`）、`addons`、`access`（access entry 與 Pod Identity）、`ec2-access`（`EC2` entry 與 `AmazonEKSAutoNodePolicy`）、`karpenter`。全部用 `mock_provider "aws"`，不連 AWS。
