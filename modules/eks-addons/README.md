# eks-addons

在一個已經建好的 EKS 叢集裡，用 Helm 裝平台元件：AWS Load Balancer Controller、Karpenter（加上預設的 NodePool 與 EC2NodeClass）、Argo Rollouts、應用程式用的 namespace，以及 0.2.0 起支援 EKS Auto Mode 的 NodeClass／NodePool、NetworkPolicy、KEDA 與 CloudWatch 採集。只用 helm provider，不用 kubernetes provider，也不建任何 AWS 資源。

每個元件的輸入是一個物件，值是 `null`（預設）就不裝，沒有 `install_xxx` 開關。

## 為什麼跟 eks-cluster 分成兩個 stack

kubernetes 與 helm provider 的文件都寫明：叢集與叢集裡的資源不要在同一個 Terraform module 裡建（設計文件 §2 第 10 點）。provider 在 plan 時就要連到叢集；叢集還不存在時，provider 設定裡的 endpoint 是未知值，plan 與 apply 都會出問題。

所以是兩個 stack、兩次 apply，順序固定：

1. `eks-cluster` 所在的 stack 先 apply，叢集、node role、Pod Identity association 都在這裡。
2. 這個 module 所在的 stack 後 apply，helm provider 的 endpoint 與 CA 取自第一個 stack 的輸出。

這個 module 因此也不依賴 aws provider，`versions.tf` 只有 `helm >= 3.0, < 4.0`。

## 用法

```hcl
module "eks_addons" {
  source = "git::https://github.com/<org>/<repo>.git//modules/eks-addons?ref=eks-addons-v0.2.0"

  cluster_name = "alpha-dev"
  region       = "ap-northeast-1"
  vpc_id       = "vpc-0123456789abcdef0"

  load_balancer_controller = {}

  karpenter = {
    interruption_queue_name = "alpha-dev" # eks-cluster 的輸出 karpenter_interruption_queue_name

    default_node_class = {
      node_role_name               = "alpha-dev-karpenter-node"
      subnet_discovery_tag         = { "karpenter.sh/discovery" = "alpha-dev" }
      security_group_discovery_tag = { "karpenter.sh/discovery" = "alpha-dev" }
    }
    default_node_pool = {}
  }

  argo_rollouts = {}

  app_namespaces = {
    apps  = { labels = { team = "platform" } }
    batch = {}
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)（用佔位值，只驗證到 `init` 與 `validate`）。

`load_balancer_controller = {}` 的意思是「要裝，全部用預設值」；`null` 才是不裝。`default_node_pool = {}` 同理。

## provider 設定

provider 由呼叫端的 stack 設定，module 裡沒有 `provider` 區塊。建議用 `exec` 跑 `aws eks get-token`：

```hcl
provider "helm" {
  kubernetes = {
    host                   = data.terraform_remote_state.cluster.outputs.endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", "alpha-dev", "--region", "ap-northeast-1"]
    }
  }
}
```

- 不要用 `aws_eks_cluster_auth` 的 `token`：它的 token 只有 15 分鐘，apply 久一點就會失敗。`exec` 每次呼叫都會重新取 token。
- 不要把 `exec` 與 `token` 混用，兩個都設時用哪一個沒有保證。
- 跑 Terraform 的環境要有 `aws` CLI，而且它的身分要在 `eks-cluster` 的 `access_entries` 裡有 cluster scope 的 `AmazonEKSClusterAdminPolicy`（Karpenter 的 CRD 與 namespace 都是 cluster scope）。
- `cluster_ca_certificate` 要的是 PEM，`eks-cluster` 輸出的是 base64，所以要 `base64decode`。

## 跟其他 module 的組裝

這個 module 不建 IAM role，也不建 Pod Identity association。三個 controller 的權限這樣接：

| 步驟 | 在哪裡 | 做什麼 |
|---|---|---|
| 1 | IAM stack | [`eks-iam-policies`](../eks-iam-policies/README.md) 輸出 `load_balancer_controller_policy_json`、`karpenter_controller_policy_json`、`argo_rollouts_cloudwatch_policy_json` |
| 2 | IAM stack | 每個 controller 用 [`iam-role`](../iam-role/README.md) 建一個 role，`trust.service_principals = ["pods.eks.amazonaws.com"]`、`tag_session = true`，policy 放 `inline_policies`。三個 policy 要各自一個 role（合在一起會超過 inline policy 上限，見 `eks-iam-policies` 的 README） |
| 3 | cluster stack | [`eks-cluster`](../eks-cluster/README.md) 的 `pod_identity_associations` 填 namespace、service account、role ARN。Karpenter 的 association 由 `karpenter.controller_role_arn` 建 |
| 4 | addons stack（這裡） | 裝 chart，`service_account` 必須跟第 3 步的 association 一致 |

預設值對得上：LB Controller 是 `kube-system` 的 `aws-load-balancer-controller`；Karpenter 是 `kube-system` 的 `karpenter`。Argo Rollouts 要用 CloudWatch analysis 時，association 要建在 `argo-rollouts` namespace 與 chart 建的 service account 上；這個 module 沒有 Argo Rollouts 的 `service_account` 輸入，名稱以 chart 預設為準（沒有在真實環境確認，要看 chart 的 `values.yaml`）。你改了這個 module 的 `namespace` 或 `service_account`，`eks-cluster` 那邊也要跟著改。

Pod Identity association 能不能在 namespace 與 service account 還不存在時先建，設計文件列為未確認（§6）。這個 stack 在後面 apply，所以順序上不受影響。

Karpenter 的 node role 就是 `eks-cluster` 的 `karpenter.node_role_arn` 那個 role，`default_node_class.node_role_name` 填同一個 role 的名稱（不是 ARN）。subnet 與 security group 用 tag 找：`vpc` module 可以加 `karpenter.sh/discovery` tag，security group 用 `security-group` 的 `tags`（設計文件 J10）。

## Karpenter 的預設 NodePool 與 EC2NodeClass

`default_node_class` 與 `default_node_pool` **兩個都有值**才會安裝本地 chart `karpenter-defaults`。其中一個是 `null` 就不裝，想自己管 NodePool 時就這樣關掉。它們是 `karpenter` 物件裡的欄位，所以 `karpenter = null` 時不可能有這些設定。

兩者的欄位：

| 欄位 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `default_node_class.node_role_name` | `string` | 必填 | Karpenter node 的 IAM role 名稱，不是 ARN |
| `default_node_class.subnet_discovery_tag` | `map(string)` | 必填 | 用 tag 選 subnet，至少一個 tag 且 key 不可為空，例如 `{ "karpenter.sh/discovery" = "alpha-dev" }` |
| `default_node_class.security_group_discovery_tag` | `map(string)` | 必填 | 用 tag 選 security group，規則同上 |
| `default_node_class.ami_alias` | `string` | `al2023@latest` | `al2023@latest` 或 `al2023@<版本>`，最多 30 字元（見下方） |
| `default_node_pool.cpu_limit` | `number` | `100` | NodePool 的 `limits.cpu`，要大於 0 |
| `default_node_pool.capacity_types` | `list(string)` | `["on-demand"]` | 只接受 `on-demand`、`spot`，不可為空或重複 |

本地 chart 建的資源（API 版本與欄位依 Karpenter v1.15.0 的 CRD 與官方範例核對）：

| 資源 | API | 內容 |
|---|---|---|
| `EC2NodeClass/default` | `karpenter.k8s.aws/v1` | `role`、`amiSelectorTerms` 的 alias（預設 `al2023@latest`）、subnet 與 security group 用 tag 選 |
| `NodePool/default` | `karpenter.sh/v1` | 照官方 `examples/v1/general-purpose.yaml`：amd64、linux、instance category `c`/`m`/`r`、generation 大於 2；`capacity-type` 與 `limits.cpu` 由輸入決定；`expireAfter: 720h`；`consolidationPolicy: WhenEmptyOrUnderutilized`、`consolidateAfter: 1m` |

EC2NodeClass 有幾項固定、沒有輸入可以改：

- `metadataOptions`：`httpTokens: required`、`httpPutResponseHopLimit: 1`。Pod 拿不到 node role。
- `blockDeviceMappings`：`/dev/xvda` 是 root volume，gp3、50Gi、`encrypted: true`（沒指定 KMS key，用帳號預設的 EBS key）。

`ami_alias` 只接受 `al2023@latest` 或 `al2023@<版本>`。Bottlerocket 的資料碟是 `/dev/xvdb`，跟這裡加密的 `/dev/xvda` 對不上，跟 `eks-cluster` 的做法一致。`@latest` 在新 AMI 發佈時會讓節點 drift 而被替換，官方不建議用在 production；要避免就釘版本，例如 `al2023@v20250101`。

alias 的格式與 30 字元上限是依 v1.15.0 CRD 的驗證規則寫的 validation；版本字串實際有哪些可以用，沒有在真實環境確認（設計文件 §6）。

## Auto Mode 的 NodeClass 與 NodePool

`auto_mode` 不是 `null` 時，裝本地 chart `auto-mode-nodes`（release 在 `kube-system`），建 `eks.amazonaws.com/v1` 的 NodeClass 與 `karpenter.sh/v1` 的 NodePool。完全不用 Auto Mode 內建的 NodePool，所以 `eks-cluster` 要先建好 node role 的 EC2 access entry。

```hcl
auto_mode = {
  node_role_name = "alpha-dev-eks-node" # IAM role 名稱，不是 ARN

  node_classes = {
    app = {
      subnet_selector_terms             = [{ tags = { "alpha/tier" = "app" } }]
      security_group_selector_terms     = [{ id = "sg-0123456789abcdef0" }, { tags = { "alpha/tier" = "node" } }]
      pod_subnet_selector_terms         = [{ tags = { "alpha/tier" = "app" } }]
      pod_security_group_selector_terms = [{ id = "sg-0fedcba9876543210" }]
    }
    system = {
      subnet_selector_terms         = [{ tags = { "alpha/tier" = "app" } }]
      security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }]
    }
  }

  node_pools = {
    app = { node_class = "app", capacity_types = ["on-demand", "spot"], cpu_limit = 200 }
    system = {
      node_class = "system"
      taints     = [{ key = "CriticalAddonsOnly", value = "true", effect = "NoSchedule" }]
      labels     = { "workload-tier" = "system" }
    }
  }
}
```

- **selector term**：每個 term 只能是 `{ id = ... }` 或 `{ tags = { ... } }` 其中一種，不能兩個都給。
- **Pod subnet 與 Pod SG 一起設**：`pod_subnet_selector_terms` 與 `pod_security_group_selector_terms` 要同時有值或同時留空，validation 會擋只設一邊。同一個 NodeClass 的所有 Pod 共用同一組 Pod SG；要讓兩種工作負載用不同的 SG，就開兩個 NodeClass 加兩個 NodePool。chart 裡另外有 `fail` 做第二道防線（只用 `helm template` 時也擋得住）。
- **`network_policy`** 預設 `DefaultDeny`，`network_policy_event_logs` 預設 `Disabled`。`DefaultDeny` 時沒有 NetworkPolicy 放行的 Pod 完全不通，所以要搭配下一節的 `network_policy`。
- **名稱**：NodeClass 不能叫 `default`；NodePool 必須指向已存在的 NodeClass。
- **NodePool 內容**：`requirements` 固定 linux，加上 `architectures`（預設 `["amd64"]`）、`capacity_types`（預設 `["on-demand"]`）與選填的 `instance_categories`（對應 `eks.amazonaws.com/instance-category`，預設不限）；`taints` 的 effect 只接受 `NoSchedule`、`PreferNoSchedule`、`NoExecute`；`limits.cpu` 是 `cpu_limit`（預設 100）。`expireAfter: 336h`、`WhenEmptyOrUnderutilized`、`consolidateAfter: 1m` 固定，沒有輸入可以改。
- 拿掉 `auto_mode` 或其中一個 pool 會刪掉 NodePool，Auto Mode 會把它的節點收掉，apply 前看 plan。
- API 版本與欄位依 AWS 文件的 NodeClass 範例（`eks.amazonaws.com/v1`）寫的，沒有對真實叢集 apply 過。

## NetworkPolicy 與 system 的放行規則

`network_policy` 不是 `null` 時裝本地 chart `system-network-policy`，做兩件事：

1. 在 `kube-system` 建 ConfigMap `amazon-vpc-cni`，`enable-network-policy-controller: "true"`，啟用 NetworkPolicy controller。叢集裡已經有同名 ConfigMap 時，Helm 會因為它不屬於這個 release 而失敗，要先處理掉。
2. 對這個 module 裝的元件各建一個 NetworkPolicy（名稱 `system-<元件>`），`policyTypes` 同時有 Ingress 與 Egress。

```hcl
network_policy = {
  service_cidr     = "172.20.0.0/16"                   # eks-cluster 輸出的 service CIDR
  api_server_cidrs = ["10.10.0.0/28", "10.10.0.16/28"] # 控制平面 ENI 所在 subnet 的 CIDR
  aws_api_cidrs    = ["10.10.1.0/28", "10.10.1.16/28"] # VPC interface endpoint 所在 subnet 的 CIDR
}
```

CIDR 由呼叫端給，module 不猜。`api_server_cidrs` 不接受 `0.0.0.0/0`；`aws_api_cidrs` 只有在沒有 VPC endpoint、走 NAT 的環境才用 `["0.0.0.0/0"]`。

每個元件的規則（port 來自 chart 的 values 與 template：LB Controller 3.6.1、KEDA 2.21.0、amazon-cloudwatch-observability 6.7.0）：

| 元件（namespace） | Ingress | Egress |
|---|---|---|
| LB Controller（`kube-system`，只選它自己的 Pod：`app.kubernetes.io/name=aws-load-balancer-controller`） | API server CIDR 到 9443/TCP（webhook，`webhookBindPort` 預設 9443） | 共用規則 |
| KEDA（`keda`，選整個 namespace） | API server CIDR 到 6443/TCP（metrics API server，`service.portHttpsTarget`）與 9443/TCP（admission webhook，`webhooks.port`）；同 namespace 到 9666/TCP（operator gRPC，`operator.metricsServiceTargetPort`） | 共用規則；同 namespace 到 9666/TCP |
| CloudWatch 採集（`amazon-cloudwatch`，選整個 namespace） | API server CIDR 到 9443/TCP（operator webhook，`manager.ports.webhookPort`） | 共用規則 |

共用的 egress：

- API server：`api_server_cidrs` 的 443/TCP。
- DNS：`service_cidr` 的 `.10`（`/32`）的 53/UDP 與 53/TCP。Auto Mode 的 CoreDNS 在每台 node 本機，位址是 service CIDR 的 `.10`（設計文件 K5）。
- AWS API：`aws_api_cidrs` 的 443/TCP。
- Pod Identity agent：`169.254.170.23/32` 的 80/TCP。拿 Pod Identity 的憑證要打這個位址，少了這條，KEDA 與 LB Controller 拿不到 AWS 權限。

幾個取捨：

- **kube-system 為什麼只放 LB Controller 的 Pod**：kube-system 還有這個 module 管不到的 Pod（例如 EKS add-on 的 metrics-server）。用 `podSelector: {}` 的整個 namespace 規則會把它們也隔離起來，所以只選 LB Controller 自己的 Pod。這依賴 chart 的 `app.kubernetes.io/name` label；你改了 chart 的 `nameOverride`，要同步調整。其他放在 kube-system 的元件（Karpenter、Argo Rollouts）不在範圍內，`DefaultDeny` 下要自己加規則。
- **KEDA 與 CloudWatch 的 namespace 由 `system-network-policy` 建**：policy 要先於 controller 存在，namespace 就得更早建好。controller 的 release 仍然帶 `create_namespace = true`，預期 Helm 在 namespace 已存在時不會失敗（沒有對真實叢集確認）。
- **metrics 的 port 沒有開**：KEDA 的 8080（Prometheus）與 8081（health）沒有來源要放行。kubelet 的探測是 node 本機的流量，預期不被擋（沒有實測，設計文件 §11 第 4 點）。之後加 Prometheus 時，另外寫一個 NetworkPolicy 放行它；NetworkPolicy 是疊加的。
- **CloudWatch agent 與 Fluent Bit 不受 NetworkPolicy 管**：chart 裡兩個 DaemonSet 都是 `hostNetwork: true`，所以這個 namespace 的 policy 實際上管的是 operator。
- **都沒有在真實叢集驗證**：Pod Identity agent 與 DNS 位址在 NetworkPolicy 下會不會被正確比對（service IP 與 DNAT 之後的位址）、探測流量，列為整合驗證（設計文件 §11 第 4 點）。

## KEDA

`keda` 裝 `kedacore/keda`（預設 `2.21.0`，namespace `keda`，operator service account `keda-operator`）。`service_account` 傳給 chart 的 `serviceAccount.operator.name`；`eks-cluster` 的 Pod Identity association 要建在這個 namespace 與 service account 上，KEDA 才能用 `aws-cloudwatch` scaler 讀 CloudWatch 指標。`values` 併進 chart values，`system_placement` 與 service account 優先。

## CloudWatch 採集

`cloudwatch_observability` 裝 `amazon-cloudwatch-observability`（預設 chart `6.7.0`，namespace `amazon-cloudwatch`）：

- Container Insights（enhanced observability）固定開（`containerInsights.enabled=true`）；`container_logs`（Fluent Bit）預設 `true`；`application_signals` 預設 `false`。
- `service_account` 預設 `cloudwatch-agent`，傳給 `agent.serviceAccount.name`。這個 chart 的 Fluent Bit DaemonSet 與 CloudWatch agent 共用同一個 service account（template 的 `cloudwatch-agent.serviceAccountName`），所以一個 Pod Identity association 涵蓋兩者。
- **不設 `system_placement`**：chart 預設 `tolerations: [{ operator: Exists }]`，DaemonSet 才會涵蓋 `app` 與 `system` 兩個 pool 的 node（設計文件 K3）。不要在 `values` 把它改掉。
- `clusterName` 與 `region` 由 module 傳入。

## system_placement

`system_placement` 把 `node_selector` 與 `tolerations` 寫進 LB Controller 與 KEDA 的 chart values 最上層（`nodeSelector`、`tolerations`），讓它們排到有 taint 的 `system` pool。跟 `values` 裡同名的 key 衝突時以 `system_placement` 為準。其他 release 不受影響。KEDA chart 頂層的 `nodeSelector`／`tolerations` 會套到 operator、metrics server、webhooks 三個 Deployment（元件自己沒設時）。

## 安裝順序

`auto_mode`、`network_policy` 與 controller 之間用 `depends_on` 明確串起來（設計文件 C5），不靠隱含相依：

```
auto_mode_nodes -> system_network_policy -> load_balancer_controller -> keda
                                                                     -> cloudwatch_observability
                                                                     -> karpenter, argo_rollouts
                                                                     -> crd_role_aggregation
```

沒有 Auto Mode 的 node 就沒地方跑；`DefaultDeny` 下沒有 policy，controller 連 API server 都連不上、webhook 也進不來。元件為 `null` 時對應的資源是空的，不影響其他元件。

`terraform test` 看不到 `depends_on`，所以用 [`tests/check-ordering.sh`](./tests/check-ordering.sh) 讀 `terraform graph` 檢查。`terraform graph` 會做 transitive reduction（`keda -> auto_mode_nodes` 這種可以由別的邊推出來的邊不會出現），所以腳本檢查的是可達性，缺任何一條都會印 `FAIL` 並回傳非零。腳本只需要 `init -backend=false`，不碰 AWS 與叢集；目前沒有接進 `scripts/validate.sh`。

## Auto Mode 與自裝 LB Controller 並存

EKS Auto Mode 內建 ALB 與 NLB 的處理，自己再裝 AWS Load Balancer Controller 就是兩個 controller 並存。`auto_mode` 有值時，module 把 LB Controller 兩個會跟 Auto Mode 搶工作的設定固定住：

- `enableServiceMutatorWebhook = false`：不讓 LB Controller 把所有新的 `type: LoadBalancer` Service 預設接走。
- `createIngressClassResource = false`：不建 `alb` IngressClass，避免跟 Auto Mode 的名稱衝突。

這兩個值用 `set` 傳，Helm 的 `set` 優先於 `values`，所以 `load_balancer_controller.values` 裡寫 `true` 也會被蓋掉（測試有涵蓋）。這時 LB Controller 只用來處理 TargetGroupBinding（`elbv2.k8s.aws/v1beta1`）。

`auto_mode = null` 時維持 chart 預設（webhook 與 IngressClass 都開）。這時若仍要跟 Auto Mode 並存，兩個 IngressClass 要用不同名稱，每個 Ingress 明確指定 `ingressClassName`，例如 `values = { ingressClass = "alb-lbc" }`，而且兩邊都不要設成 default IngressClass。

預設 chart 版本是 `3.6.1`（0.1.0 是 `3.6.0`）。Auto Mode 與自裝 controller 並存實際會不會互相干擾，沒有在真實環境確認（設計文件 §11 第 2 點）。

## private cluster 的 chart mirror

沒有對外連線的環境，跑 Terraform 的機器要能抓到 chart。把 chart 同步到內部的 registry（例如 ECR），用 `chart_repository_overrides` 指過去：

```hcl
chart_repository_overrides = {
  load_balancer_controller = "oci://111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/charts"
  karpenter                = "oci://111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/charts"
  argo_rollouts            = "oci://111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/charts"
  keda                     = "oci://111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/charts"
  cloudwatch_observability = "oci://111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/charts"
}
```

- key 只有 `load_balancer_controller`、`karpenter`、`argo_rollouts`、`keda`、`cloudwatch_observability`；值要是 `https://` 或 `oci://`。
- mirror 裡的 chart 名稱與版本要跟預設一樣（`aws-load-balancer-controller`、`karpenter`、`argo-rollouts`、`keda`、`amazon-cloudwatch-observability`），module 只換 repository，不換 chart 名稱。
- 抓 ECR 要登入。helm provider 的 `registries` 區塊接受 `url`、`username`、`password`，密碼可以用 `aws_ecr_authorization_token`（12 小時有效）；這個接法沒有實測，列為未確認。
- chart 的 image 也要在 mirror：用各 chart 自己的 values 改 image repository，從 `values` 傳進去。每個 chart 都一樣。
- 五個本地 chart（`karpenter-defaults`、`app-namespaces`、`auto-mode-nodes`、`system-network-policy`、`crd-role-aggregation`）隨 module 一起，不需要 mirror。

## CI 用 Helm 部署應用程式的權限

CI 部署應用程式用的權限不在這個 module，在 `eks-cluster` 的 `access_entries`（見 [`eks-cluster` 的 README](../eks-cluster/README.md) 的「CI 用 Helm 部署的最小權限」）：

- 給 CI 的 deploy role 一個 `STANDARD` access entry，關聯 namespace scope 的 `AmazonEKSEditPolicy`。Helm 的 release 紀錄存在 Secret，Edit 含 Secret 的讀寫，所以夠用。IAM 端只要 `eks:DescribeCluster`。
- chart 會建 Role 或 RoleBinding 時要用 namespace scope 的 `AmazonEKSAdminPolicy`；Edit 不含 roles 與 rolebindings。
- Edit 含 serviceaccount 的 `impersonate`，有這個風險。
- CI 裝不了 CRD 與 cluster scope 的資源，也建不了 namespace。CRD 由這個 module 裝，namespace 由 `app_namespaces` 建，所以 CI 部署的 namespace 要先列在 `app_namespaces`。
- Edit 與 Admin 對應 Kubernetes 內建的 `edit`、`admin` ClusterRole，只會帶到有 aggregate label 的 CRD 權限。LB Controller 3.6.1 的 chart 沒有這種 ClusterRole，KEDA 2.21.0 的 chart 有但預設關閉（`rbac.aggregateToDefaultRoles: false`）。chart 要建 TargetGroupBinding 或 ScaledObject 時，設 `aggregate_crd_roles = true`（0.3.0 起）：
  - LB Controller 有裝時，裝本地 chart `crd-role-aggregation`（release 在 `kube-system`），建 `eks-addons:targetgroupbindings-edit`（create、delete、deletecollection、patch、update，併進 edit 與 admin）與 `eks-addons:targetgroupbindings-view`（get、list、watch，併進 view、edit 與 admin）。
  - KEDA 有裝時，用 `set` 把 `rbac.aggregateToDefaultRoles` 設成 `true`，`keda.values` 改不回來。

## 注意

- **用 atomic，不只是 wait。** 所有 release 都開 `atomic = true`、`cleanup_on_fail = true`；controller 的 `timeout` 是 600 秒，本地 chart 是 300 秒。依 helm provider 的說明，`atomic` 在失敗時清掉安裝，而且會自動開 `wait`，所以 apply 要等 Pod 都 ready 才算成功，升級失敗會 rollback。只開 `wait` 的話，失敗的安裝會留下 failed release，要手動處理。代價是失敗時要等到 timeout 才看得到結果。這些值沒有輸入可以調。
- **安裝順序。** 見上面〈安裝順序〉一節。另外 `karpenter-defaults` 依賴 `karpenter`（CRD 要先在）；`karpenter` 與 `argo_rollouts` 依賴 LB Controller，因為 LB Controller 註冊了 Service 的 mutating webhook，它沒 ready 時其他 chart 建 Service 可能失敗（這是依 webhook 的運作方式推的，沒有實測）。
- **`values` 與內建欄位的優先順序。** `load_balancer_controller.values`、`karpenter.values` 與 `argo_rollouts.values` 用 YAML 傳給 chart。module 另外用 `set` 傳 `clusterName`、`region`、`vpcId`、`serviceAccount.name`、`replicaCount`（LB Controller）與 `settings.clusterName`、`settings.interruptionQueue`、`serviceAccount.name`（Karpenter）。Helm 的 `set` 優先於 values，所以 `values` 裡同名的 key 會被蓋掉。Argo Rollouts 沒有 `set`。
- **chart 版本是精確版本。** `chart_version` 只接受 `3.6.0` 這種格式（可以帶 `-rc.1`），不接受 `v3.6.0`、`latest`、版本範圍。預設值（LB Controller `3.6.1`、Karpenter `1.15.0`、Argo Rollouts `2.43.8`）跟 `eks-iam-policies` 的 policy 版本綁在一起，改 chart 版本要確認 policy 還對得上。
- **Karpenter chart 1.15.0 存在於 `public.ecr.aws/karpenter/karpenter`。** 2026-10-21 用匿名的 public ECR registry API 查過 manifest（HTTP 200）。`v1.15.0` tag 裡的 `charts/karpenter/Chart.yaml` 寫 `1.14.1`，是官方發佈時才改版號，不影響。
- **本地 chart 改了要升版號。** module 把 `Chart.yaml` 的 `version` 傳給 release 的 `version`，改 chart 內容時同步升版號，release 才會被判定要更新。
- **namespace 拿掉就是整個刪掉。** `app_namespaces` 拿掉一個 key，或整個 release 被移除，那個 namespace 與裡面所有東西都會被刪。同理拿掉 `default_node_pool` 會刪 NodePool，Karpenter 會把它的節點收掉。apply 前看 plan。
- **namespace 名稱限制。** `app_namespaces` 的 key 必須是 RFC 1123 label（63 字元內的小寫英數與連字號），不能是 `default` 或 `kube-` 開頭（本來就存在，Helm 會因為已存在而失敗）。也不要跟 Karpenter、Argo Rollouts 的 namespace 同名，這兩個由各自的 release 建，這個衝突 module 不檢查。
- **`create_namespace`。** Karpenter 與 Argo Rollouts 的 release 帶 `create_namespace = true`，namespace 是 `kube-system` 時沒有影響。LB Controller 固定在 `kube-system`，沒有 namespace 輸入。
- **`replica_count` 預設 2**（高可用）；單節點的測試叢集可以調成 1。
- **離線測試驗不到的事**（設計文件 §6）：EC2NodeClass alias 實際可用的版本字串、LB Controller 用 Pod Identity 的行為、Argo Rollouts 用 Pod Identity 讀 CloudWatch。測試用 `mock_provider "helm"`，只驗證 plan 的內容，沒有對真實叢集 apply 過。

## 刻意不做

- IAM role 與 Pod Identity association（用 `iam-role` 與 `eks-cluster`；policy JSON 來自 `eks-iam-policies`）。
- `install_xxx` 開關（物件為 `null` 就不裝）。
- kubernetes provider 與 `kubernetes_manifest`：它在 plan 時就要連叢集讀 CRD。NodePool、EC2NodeClass 與 namespace 改用本地 chart 經 `helm_release` 安裝（設計文件 J5）。
- 可以調的 NodePool 規格（arch、instance family、expireAfter、disruption budget）與 EC2NodeClass 的 userData、kubelet、磁碟大小。要自訂請把 `default_node_pool` 或 `default_node_class` 設成 `null`，自己管。
- Bottlerocket、arm64 的預設 NodePool。
- metrics-server（用 `eks-cluster` 的 EKS add-on，設計文件 J6）。
- 其他 Helm chart、Gateway API、ArgoCD、監控元件。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `cluster_name` | `string` | 無 | 是 | EKS cluster 名稱，傳給 AWS Load Balancer Controller 與 Karpenter。1–100 字元，限英數字、`-`、`_`，首字元須為英數字。 |
| `region` | `string` | 無 | 是 | cluster 所在 region，例如 `ap-northeast-1`。傳給 AWS Load Balancer Controller：hop limit 為 1 時它讀不到 IMDS，所以明確傳入。 |
| `vpc_id` | `string` | 無 | 是 | cluster 的 VPC ID，格式像 `vpc-0123456789abcdef0`。傳給 AWS Load Balancer Controller：hop limit 為 1 時它讀不到 IMDS，所以明確傳入。 |
| `load_balancer_controller` | `object` | `null` | 否 | AWS Load Balancer Controller 的 release，namespace 固定 `kube-system`；`null` 不裝。欄位：`chart_version`（預設 `3.6.1`，精確版本）、`service_account`（預設 `aws-load-balancer-controller`）、`replica_count`（預設 `2`，至少 1 的整數）、`values`（預設 `{}`，併進 chart values，衝突時以前面的欄位為準）。IAM role 不在這裡建，service account 的 Pod Identity association 在 `eks-cluster`。設了 `auto_mode` 時 `enableServiceMutatorWebhook` 與 `createIngressClassResource` 固定為 `false`，`values` 改不回來。 |
| `karpenter` | `object` | `null` | 否 | Karpenter controller 的 release；`null` 不裝。欄位：`chart_version`（預設 `1.15.0`，精確版本）、`namespace`（預設 `kube-system`）、`service_account`（預設 `karpenter`）、`interruption_queue_name`（必填，SQS queue 名稱，不是 URL 或 ARN，即 `eks-cluster` 的輸出 `karpenter_interruption_queue_name`）、`values`（預設 `{}`）、`default_node_class` 與 `default_node_pool`（預設 `null`，兩個都有值才裝本地 chart `karpenter-defaults`；`default_node_pool = {}` 表示用預設限制）。這兩個的欄位見〈Karpenter 的預設 NodePool 與 EC2NodeClass〉。 |
| `argo_rollouts` | `object` | `null` | 否 | Argo Rollouts 的 release；`null` 不裝。欄位：`chart_version`（預設 `2.43.8`，精確版本）、`namespace`（預設 `argo-rollouts`）、`values`（預設 `{}`，併進 chart values）。CloudWatch 指標分析要的 role 與 Pod Identity association 在 `eks-cluster` 建。 |
| `app_namespaces` | `map(object)` | `{}` | 否 | 用本地 chart `app-namespaces` 建的應用程式 namespace，key 是 namespace 名稱（RFC 1123 label，不能是 `default` 或 `kube-` 開頭），欄位 `labels` 預設 `{}`；空 map 不裝。掛 Edit access policy 的 CI role 建不了 namespace，所以在這裡建。 |
| `auto_mode` | `object` | `null` | 否 | EKS Auto Mode 的 NodeClass 與 NodePool（本地 chart `auto-mode-nodes`，`eks.amazonaws.com/v1` NodeClass 與 `karpenter.sh/v1` NodePool）；`null` 不裝。有值時也會把 AWS Load Balancer Controller 的 `enableServiceMutatorWebhook` 與 `createIngressClassResource` 固定為 `false`。欄位見〈`auto_mode` 欄位〉。 |
| `network_policy` | `object` | `null` | 否 | 啟用 NetworkPolicy controller（`kube-system` 的 ConfigMap `amazon-vpc-cni` 設 `enable-network-policy-controller`），並替這個 module 有裝的元件建 system NetworkPolicy（本地 chart `system-network-policy`）；`null` 兩者都不做。欄位都必填，CIDR 由呼叫端給：`service_cidr`（cluster 的 IPv4 service CIDR，DNS 是它的 `.10`）、`api_server_cidrs`（control plane ENI 所在 subnet，不可為空，不接受 `0.0.0.0/0`）、`aws_api_cidrs`（VPC interface endpoint 所在 subnet，不可為空；只有經 NAT 連 AWS API 時才用 `["0.0.0.0/0"]`）。規則見〈NetworkPolicy 與 system 的放行規則〉。 |
| `system_placement` | `object` | `null` | 否 | AWS Load Balancer Controller 與 KEDA（該跑在 system node pool 的 Deployment）的 node selector 與 toleration；`null` 不改它們的排程。寫在 chart values 最上層，跟元件 `values` 同名的 key 衝突時以這裡為準。欄位：`node_selector`（預設 `{}`，key 不可為空）、`tolerations`（預設 `[]`，每項的 `key`、`operator`、`value`、`effect` 都選填；`operator` 為 `Equal` 或 `Exists`，`effect` 為 `NoSchedule`、`PreferNoSchedule` 或 `NoExecute`）。CloudWatch 採集不套用，它的 DaemonSet 要涵蓋每個 node。 |
| `keda` | `object` | `null` | 否 | KEDA 的 release（chart `kedacore/keda`）；`null` 不裝。欄位：`chart_version`（預設 `2.21.0`，精確版本）、`namespace`（預設 `keda`）、`service_account`（預設 `keda-operator`，operator 的 service account，CloudWatch scaler 的 Pod Identity association 建在它上面，在 `eks-cluster`）、`values`（預設 `{}`，併進 chart values，衝突時以 `system_placement` 與 service account 為準）。 |
| `cloudwatch_observability` | `object` | `null` | 否 | Amazon CloudWatch Observability 的 release（chart `amazon-cloudwatch-observability`）；`null` 不裝。Container Insights（enhanced observability）固定開。欄位：`chart_version`（預設 `6.7.0`，精確版本）、`namespace`（預設 `amazon-cloudwatch`）、`service_account`（預設 `cloudwatch-agent`，CloudWatch agent 與 Fluent Bit 共用，一個 Pod Identity association 涵蓋兩者）、`container_logs`（預設 `true`，開 Fluent Bit）、`application_signals`（預設 `false`）、`values`（預設 `{}`，併進 chart values，衝突時以前面的欄位為準）。chart 預設容忍所有 taint，刻意保留。 |
| `aggregate_crd_roles` | `bool` | `false` | 否 | 把應用程式 chart 會建的自訂資源權限併進內建的 `view`、`edit`、`admin` role，讓 namespace scope 的 Edit 或 Admin（例如掛 `AmazonEKSEditPolicy` 的 CI role）能管理：有裝 AWS Load Balancer Controller 時用本地 chart `crd-role-aggregation` 加 TargetGroupBinding；有裝 KEDA 時用 KEDA chart 的 `rbac.aggregateToDefaultRoles` 加 ScaledObject、TriggerAuthentication 等 KEDA 資源。見〈CI 用 Helm 部署應用程式的權限〉。 |
| `chart_repository_overrides` | `map(string)` | `{}` | 否 | 各元件的 chart repository URL，例如 private cluster 的 ECR mirror。key 只能是 `load_balancer_controller`、`karpenter`、`argo_rollouts`、`keda`、`cloudwatch_observability`；值要是 `https://` 或 `oci://` URL。預設 repository 見〈預設 chart repository〉。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `releases` | 每個已安裝 release 的 `name`、`namespace` 與 chart `version`，key 是元件：`load_balancer_controller`、`karpenter`、`karpenter_defaults`、`argo_rollouts`、`app_namespaces`、`auto_mode_nodes`、`system_network_policy`、`keda`、`cloudwatch_observability`、`crd_role_aggregation`。沒裝的元件不會出現。 |
<!-- END_TF_DOCS -->

## `auto_mode` 欄位

`auto_mode` 的欄位（用法見〈Auto Mode 的 NodeClass 與 NodePool〉）：

| 欄位 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `node_role_name` | `string` | 必填 | node role 的 IAM role 名稱（不是 ARN），`eks-cluster` 要先替它建 EC2 access entry |
| `node_classes` | `map(object)` | 必填 | 至少一個；key 是 NodeClass 名稱（RFC 1123 label），不能叫 `default` |
| `node_pools` | `map(object)` | 必填 | 至少一個；key 是 NodePool 名稱（RFC 1123 label） |

`node_classes` 每項的欄位：

| 欄位 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `subnet_selector_terms` | `list(object)` | 必填 | 至少一個 selector term |
| `security_group_selector_terms` | `list(object)` | 必填 | 至少一個 selector term |
| `pod_subnet_selector_terms` | `list(object)` | `[]` | 跟 `pod_security_group_selector_terms` 要一起設或一起留空 |
| `pod_security_group_selector_terms` | `list(object)` | `[]` | Pod SG 是 NodeClass 層級的設定，同一個 NodeClass 的 Pod 共用 |
| `network_policy` | `string` | `DefaultDeny` | `DefaultDeny` 或 `DefaultAllow` |
| `network_policy_event_logs` | `string` | `Disabled` | `Enabled` 或 `Disabled` |

selector term 是 `{ id = "..." }` 或 `{ tags = { ... } }`，只能給一種，`tags` 不可為空。subnet 的 `id` 格式像 `subnet-0123456789abcdef0`，security group 的 `id` 格式像 `sg-0123456789abcdef0`。

`node_pools` 每項的欄位：

| 欄位 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `node_class` | `string` | 必填 | 必須是 `node_classes` 的 key |
| `taints` | `list(object)` | `[]` | 每項 `key`（不可為空）、`value`（選填）、`effect`（`NoSchedule`、`PreferNoSchedule`、`NoExecute`） |
| `labels` | `map(string)` | `{}` | 節點 label |
| `capacity_types` | `list(string)` | `["on-demand"]` | `on-demand`、`spot`，不可為空或重複 |
| `instance_categories` | `list(string)` | `[]` | 例如 `c`、`m`、`r`（1–4 個小寫字母）；空的代表不限 |
| `architectures` | `list(string)` | `["amd64"]` | `amd64`、`arm64`，不可為空或重複 |
| `cpu_limit` | `number` | `100` | NodePool 的 `limits.cpu`，要大於 0 |

## 預設 chart repository

預設 repository：LB Controller `https://aws.github.io/eks-charts`（chart `aws-load-balancer-controller`）、Karpenter `oci://public.ecr.aws/karpenter`（chart `karpenter`）、Argo Rollouts `https://argoproj.github.io/argo-helm`（chart `argo-rollouts`）、KEDA `https://kedacore.github.io/charts`（chart `keda`）、CloudWatch 採集 `https://aws-observability.github.io/helm-charts`（chart `amazon-cloudwatch-observability`）。

## 測試

```bash
scripts/validate.sh modules/eks-addons
```

`tests/releases.tftest.hcl` 驗證哪些 release 會建與傳給 chart 的值：物件為 `null` 時沒有 release、chart 版本預設值、LB Controller 的 `clusterName`、`region`、`vpcId`、Karpenter 的 `settings.clusterName` 與 `settings.interruptionQueue`、`karpenter-defaults` 的安裝條件、`app_namespaces`、`chart_repository_overrides`、輸出。`tests/auto-mode.tftest.hcl`（NodeClass 的 selector 與 Pod 欄位成對、NodePool 的 taint、LB Controller 在 Auto Mode 下被固定的兩個旗標）、`tests/network-policy.tftest.hcl`（ConfigMap 開關、各元件的 port 與 CIDR，含 DNS 53 UDP 與 TCP）、`tests/addons.tftest.hcl`（KEDA 與 CloudWatch 的版本、namespace、service account、Application Signals 關閉、`system_placement`）驗證 0.2.0 的輸入，這些輸入預設全部是關的。`tests/crd-roles.tftest.hcl` 驗證 `aggregate_crd_roles`：預設關閉、只在 LB Controller 有裝時裝 `crd-role-aggregation`、KEDA 的 `set` 蓋過 `values`。`tests/validation.tftest.hcl` 與 `tests/validation-new-inputs.tftest.hcl` 每條 validation 正反各測。`tests/check-ordering.sh` 檢查安裝順序（見〈安裝順序〉）。全部用 `mock_provider "helm"`，不連叢集。

五個本地 chart 由 `scripts/validate.sh` 在本機有 `helm` 時跑 `helm lint` 與 `helm template`（CI 已安裝 helm）。本機沒有 `helm` 時 `validate.sh` 會印「略過 helm lint」，代表 chart 沒被檢查。

`validate.sh` 不檢查 chart 輸出是否符合 Karpenter 的 CRD。EC2NodeClass 的固定欄位可以手動確認：

```bash
helm template x modules/eks-addons/charts/karpenter-defaults | grep -E 'httpTokens|httpPutResponseHopLimit|encrypted'
```

新的兩個 chart 可以手動確認渲染結果：

```bash
helm template x modules/eks-addons/charts/auto-mode-nodes
helm template x modules/eks-addons/charts/system-network-policy
```
