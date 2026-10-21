# eks-addons

在一個已經建好的 EKS 叢集裡，用 Helm 裝平台元件：AWS Load Balancer Controller、Karpenter（加上預設的 NodePool 與 EC2NodeClass）、Argo Rollouts，以及應用程式用的 namespace。只用 helm provider，不用 kubernetes provider，也不建任何 AWS 資源。

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
  source = "git::https://github.com/<org>/<repo>.git//modules/eks-addons?ref=eks-addons-v0.1.0"

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

## Auto Mode 與自裝 LB Controller 並存

EKS Auto Mode 內建 ALB 與 NLB 的處理，自己再裝 AWS Load Balancer Controller 就是兩個 controller 並存。兩者要用 IngressClass 分開，每個 Ingress 明確指定 `ingressClassName`：

- LB Controller 的 chart 預設建一個叫 `alb` 的 IngressClass（`ingressClass: alb`、`createIngressClassResource: true`，v3.6.0 的 `values.yaml` 確認過）。Auto Mode 的 IngressClass 也可能取名 `alb`，名稱衝突時請把其中一個改掉，例如：

  ```hcl
  load_balancer_controller = {
    values = { ingressClass = "alb-lbc" }
  }
  ```

- 兩邊都不要設成 default IngressClass，沒有指定 `ingressClassName` 的 Ingress 才不會被誰默默接手。

Auto Mode 與自裝 controller 並存實際會不會互相干擾，沒有在真實環境確認。

## private cluster 的 chart mirror

沒有對外連線的環境，跑 Terraform 的機器要能抓到 chart。把 chart 同步到內部的 registry（例如 ECR），用 `chart_repository_overrides` 指過去：

```hcl
chart_repository_overrides = {
  load_balancer_controller = "oci://111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/charts"
  karpenter                = "oci://111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/charts"
  argo_rollouts            = "oci://111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/charts"
}
```

- key 只有 `load_balancer_controller`、`karpenter`、`argo_rollouts`；值要是 `https://` 或 `oci://`。
- mirror 裡的 chart 名稱與版本要跟預設一樣（`aws-load-balancer-controller`、`karpenter`、`argo-rollouts`），module 只換 repository，不換 chart 名稱。
- 抓 ECR 要登入。helm provider 的 `registries` 區塊接受 `url`、`username`、`password`，密碼可以用 `aws_ecr_authorization_token`（12 小時有效）；這個接法沒有實測，列為未確認。
- chart 的 image 也要在 mirror：用各 chart 自己的 values 改 image repository，從 `values` 傳進去。三個 controller 都一樣。
- 兩個本地 chart 隨 module 一起，不需要 mirror。

## CI 用 Helm 部署應用程式的權限

CI 部署應用程式用的權限不在這個 module，在 `eks-cluster` 的 `access_entries`（見 [`eks-cluster` 的 README](../eks-cluster/README.md) 的「CI 用 Helm 部署的最小權限」）：

- 給 CI 的 deploy role 一個 `STANDARD` access entry，關聯 namespace scope 的 `AmazonEKSEditPolicy`。Helm 的 release 紀錄存在 Secret，Edit 含 Secret 的讀寫，所以夠用。IAM 端只要 `eks:DescribeCluster`。
- chart 會建 Role 或 RoleBinding 時要用 namespace scope 的 `AmazonEKSAdminPolicy`；Edit 不含 roles 與 rolebindings。
- Edit 含 serviceaccount 的 `impersonate`，有這個風險。
- CI 裝不了 CRD 與 cluster scope 的資源，也建不了 namespace。CRD 由這個 module 裝，namespace 由 `app_namespaces` 建，所以 CI 部署的 namespace 要先列在 `app_namespaces`。

## 注意

- **用 atomic，不只是 wait。** 所有 release 都開 `atomic = true`、`cleanup_on_fail = true`；controller 的 `timeout` 是 600 秒，本地 chart 是 300 秒。依 helm provider 的說明，`atomic` 在失敗時清掉安裝，而且會自動開 `wait`，所以 apply 要等 Pod 都 ready 才算成功，升級失敗會 rollback。只開 `wait` 的話，失敗的安裝會留下 failed release，要手動處理。代價是失敗時要等到 timeout 才看得到結果。這些值沒有輸入可以調。
- **安裝順序。** `karpenter-defaults` 依賴 `karpenter`（CRD 要先在）；`karpenter` 與 `argo_rollouts` 依賴 LB Controller，因為 LB Controller 註冊了 Service 的 mutating webhook，它沒 ready 時其他 chart 建 Service 可能失敗（這是依 webhook 的運作方式推的，沒有實測）。
- **`values` 與內建欄位的優先順序。** `load_balancer_controller.values` 與 `argo_rollouts.values` 用 YAML 傳給 chart。module 另外用 `set` 傳 `clusterName`、`region`、`vpcId`、`serviceAccount.name`、`replicaCount`（LB Controller）與 `settings.clusterName`、`settings.interruptionQueue`、`serviceAccount.name`（Karpenter）。Helm 的 `set` 優先於 values，所以 `values` 裡同名的 key 會被蓋掉。Karpenter 沒有 `values` 輸入，Argo Rollouts 沒有 `set`。
- **chart 版本是精確版本。** `chart_version` 只接受 `3.6.0` 這種格式（可以帶 `-rc.1`），不接受 `v3.6.0`、`latest`、版本範圍。預設值（LB Controller `3.6.0`、Karpenter `1.15.0`、Argo Rollouts `2.43.8`）跟 `eks-iam-policies` 的 policy 版本綁在一起，改 chart 版本要確認 policy 還對得上。
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

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `cluster_name` | `string` | 無 | 是 | EKS 叢集名稱 |
| `region` | `string` | 無 | 是 | 叢集所在 region，傳給 LB Controller |
| `vpc_id` | `string` | 無 | 是 | 叢集的 VPC ID，傳給 LB Controller（hop limit 1 時它讀不到 IMDS） |
| `load_balancer_controller` | `object({ chart_version, service_account, replica_count, values })` | `null` | 否 | 預設 `3.6.0`、`aws-load-balancer-controller`、`2`、`{}`；namespace 固定 `kube-system`；`null` 不裝 |
| `karpenter` | `object({ chart_version, namespace, service_account, interruption_queue_name, values, default_node_class, default_node_pool })` | `null` | 否 | 預設 `1.15.0`、`kube-system`、`karpenter`；`interruption_queue_name` 必填；`null` 不裝 |
| `karpenter.default_node_class` | `object({ node_role_name, subnet_discovery_tag, security_group_discovery_tag, ami_alias })` | `null` | 否 | `node_role_name` 是 IAM role 名稱；兩個 tag 是 `map(string)`（至少一個）；`ami_alias` 預設 `al2023@latest` |
| `karpenter.default_node_pool` | `object({ cpu_limit, capacity_types })` | `null` | 否 | `cpu_limit` 預設 `100`（要大於 0）；`capacity_types` 預設 `["on-demand"]`，只接受 `on-demand`、`spot`；與 `default_node_class` 都有值才安裝 `karpenter-defaults` |
| `argo_rollouts` | `object({ chart_version, namespace, values })` | `null` | 否 | 預設 `2.43.8`、`argo-rollouts`、`{}`；`null` 不裝 |
| `app_namespaces` | `map(object({ labels }))` | `{}` | 否 | key 是 namespace 名稱，`labels` 預設 `{}`；空的不裝 |
| `chart_repository_overrides` | `map(string)` | `{}` | 否 | key 是 `load_balancer_controller`、`karpenter`、`argo_rollouts`；值是 `https://` 或 `oci://` URL |

預設 repository：LB Controller `https://aws.github.io/eks-charts`（chart `aws-load-balancer-controller`）、Karpenter `oci://public.ecr.aws/karpenter`（chart `karpenter`）、Argo Rollouts `https://argoproj.github.io/argo-helm`（chart `argo-rollouts`）。

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `releases` | `map(object({ name, namespace, version }))` | 每個已安裝 release 的名稱、namespace 與 chart 版本。key 是 `load_balancer_controller`、`karpenter`、`karpenter_defaults`、`argo_rollouts`、`app_namespaces`；沒裝的元件不會出現 |

## 測試

```bash
scripts/validate.sh modules/eks-addons
```

`tests/releases.tftest.hcl` 驗證哪些 release 會建與傳給 chart 的值：物件為 `null` 時沒有 release、chart 版本預設值、LB Controller 的 `clusterName`、`region`、`vpcId`、Karpenter 的 `settings.clusterName` 與 `settings.interruptionQueue`、`karpenter-defaults` 的安裝條件、`app_namespaces`、`chart_repository_overrides`、輸出。`tests/validation.tftest.hcl` 每條 validation 正反各測。全部用 `mock_provider "helm"`，不連叢集。

兩個本地 chart 由 `scripts/validate.sh` 在本機有 `helm` 時跑 `helm lint` 與 `helm template`（CI 已安裝 helm）。本機沒有 `helm` 時 `validate.sh` 會印「略過 helm lint」，代表 chart 沒被檢查。

`validate.sh` 不檢查 chart 輸出是否符合 Karpenter 的 CRD。EC2NodeClass 的固定欄位可以手動確認：

```bash
helm template x modules/eks-addons/charts/karpenter-defaults | grep -E 'httpTokens|httpPutResponseHopLimit|encrypted'
```
