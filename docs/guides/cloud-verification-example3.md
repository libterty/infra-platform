# example3 雲端驗證 runbook

## 結論

這份 runbook 列出 `templates/example3` 第一次在真實 AWS 帳號 apply 時要逐項確認的事，照做完就能把 README〈雲端整合待驗證〉表與 design v4 §11 的「未實測」改成有證據的結論。

- 範圍：README 表上的 10 項、design §11 裡表上沒涵蓋的 10 項（本文 S1–S10），加上 `modules/xray-transaction-search`（本文 X）。
- 每一項都有：前提（要 apply 哪些 stack、tfvars 怎麼設）、指令、預期結果、結果紀錄。
- 指令預設都是唯讀。會改變狀態的指令標【寫入】，只在 `dev` 執行。
- 這份文件的指令都**沒有實際跑過**，名稱與數值都從程式碼推出來，出處寫在每段的「名稱怎麼來的」。標「推測」的是 repo 以外的慣例（chart 或 AWS 的預設命名），執行時以實際輸出為準。
- 寫這份 runbook 時從程式碼找到、已經修正的：no-NAT 的 interface endpoint 原本缺 `secretsmanager`（api 與 worker 都要讀 Secrets Manager），已加進 `network/endpoints.tf`。
- 從程式碼就看得出來、第一次驗證很可能不通過的兩件事，先講：
  1. **no-NAT 時平台元件的映像來源**：`eks-addons` 只處理 chart 的來源（`chart_repository_overrides`），LB Controller、KEDA、CloudWatch 採集的 container image 用 chart 預設的公開 registry（推測，repo 裡沒有覆寫映像來源的設定）。沒有 NAT 時很可能拉不到。
  2. **CI 的 `AmazonEKSEditPolicy` 不一定吃得到 RBAC aggregation**：`aggregate_crd_roles` 把 CRD 權限併進 Kubernetes 內建的 `edit` ClusterRole；EKS access policy 是 EKS 自己的 authorizer 判斷，不一定會參考 `edit` 的內容（推測，design §11 第 15 點列為待確認）。第 10 項的 `kubectl auth can-i` 會直接回答這件事。

## 範圍

涵蓋：

| 編號 | 項目 | 來源 |
|---|---|---|
| 1–10 | node 加入叢集、DNS、Pod Identity、TargetGroupBinding、KEDA、CloudWatch 採集、告警、no-NAT、canary、CI 權限 | `templates/example3/infra/README.md:463-474` |
| S1–S10 | design §11 裡上表沒涵蓋的部分（對照見下表） | `docs/design/v4/design-docs.md` §11 |
| X | X-Ray Transaction Search | `modules/xray-transaction-search/README.md:30-35` |

design §11 各點的去處：

| §11 | 內容 | 在本文 |
|---|---|---|
| 1 | node 與 pod 共用 subnet、IP 預算 | S1 |
| 2 | 兩個 load balancing controller 並存 | S2 |
| 3 | `app` SG 補的 kubelet 探測與 DNS 規則 | S4（DNS 部分在第 2 項） |
| 4 | `DefaultDeny` 下系統元件的 webhook 與 metrics | S4 |
| 5 | Pod Identity association 早於 namespace 與 ServiceAccount | S5 |
| 6 | LB Controller 對 Terraform 建的 target group 做 `RegisterTargets` | 第 4 項 |
| 7 | helm provider 用 SSM 讀到的值 | S6 |
| 8 | no-NAT 的 interface endpoint | 第 8 項 |
| 9 | KEDA 對長連線（SSE）的效果 | S10（觀察資料放在第 5 項） |
| 10 | 已由第 17 點取代 | 第 6 項 |
| 11 | Kubernetes 版本 1.36 | S7 |
| 12 | 保密的來源字串比對 | 不在本文：離線檢查，不需要雲端 |
| 13 | 不開內建 NodePool 時 NodeClass／NodePool CRD 是否存在 | S3 |
| 14 | `amazon-vpc-cni` ConfigMap 是否已存在 | S3 |
| 15 | CI 的 Edit 能不能建 CRD | 第 10 項 |
| 16 | secrets 加密的 KMS grant | S8 |
| 17 | Container Insights application log group 的建立時間與保留期 | S9 |
| §8.2 | `tcp_keepalive_*` sysctl、SDK 支援 Pod Identity | S10 前段、第 3 項 |

不涵蓋：README〈已知限制〉裡沿用 example2 的項目（RDS Proxy 的 KMS、Enhanced Monitoring、AgentCore role、bastion、ALB access log、WAF logging、guardrail、pg_cron 字串、import-load 觸發）。它們在 `docs/design/v2/design-docs.md` §5.8、§5.10 追蹤。

## 需要的權限與工具

工具：

- AWS CLI v2（要有 `eks list-pod-identity-associations`、`eks describe-cluster-versions`）、`jq`、Terraform（apply 用）。
- `kubectl`，版本跟叢集差一個 minor 以內（叢集 placeholder 是 1.36，`eks-cluster/envs/dev.tfvars:7`）。
- `helm` 3（只用 `helm list`，以及 README〈部署〉的 CI 部署）。
- 一個有 `dig` 的除錯映像（第 2 項用）。repo 沒有提供，下面寫成 `<debug-image>`；沒有 NAT 時要先推進自己的 ECR。

身分：

| 用途 | 身分 | 依據 |
|---|---|---|
| apply 前 7 個 stack 與其他不碰 Kubernetes API 的 stack | 各 stack 的 apply 身分；`eks-cluster` 的身分要有 secrets key 的 `kms:CreateGrant`、`kms:DescribeKey` | README〈執行環境〉 |
| apply `eks-addons` | 必須是 `eks-cluster` 的 `addons_apply_principal_arn` | `eks-addons/providers.tf:2`、README:123 |
| CI 部署 api、worker | `eks-cluster` 的 `ci_deploy_principal_arn` | README:300 |
| 執行本文的 `kubectl` | `cluster_admin_principal_arns` 裡的一個 | `eks-cluster/cluster.tf:32-36` |
| 第 10 項 | 能 assume `ci_deploy_principal_arn`，或直接在 CI runner 上跑 | — |

驗證身分要的 AWS 權限（唯讀）：`eks:Describe*`、`eks:List*`、`elasticloadbalancing:Describe*`、`cloudwatch:DescribeAlarms`、`cloudwatch:ListMetrics`、`cloudwatch:GetMetricStatistics`、`logs:Describe*`、`logs:FilterLogEvents`、`logs:TestMetricFilter`、`ssm:GetParameter`、`ec2:Describe*`、`cloudtrail:LookupEvents`、`sns:ListSubscriptionsByTopic`、`kms:ListGrants`、`kms:DescribeKey`、`xray:GetTraceSegmentDestination`、`xray:GetIndexingRules`。

【寫入】要另外的權限：`cloudwatch:SetAlarmState`、`cloudwatch:PutMetricData`。`kubectl exec`、`kubectl debug`、`kubectl delete`、`kubectl annotate` 用叢集管理者身分。

網路：叢集只有 private endpoint，所有 `kubectl`、`helm` 要在 VPC 或可連通的網路執行，而且來源要列在 `network` 的 `k8s_api_sources`（`network/variables.tf:100`）。兩份 `network/envs/*.tfvars` 都沒設這個變數，預設是空的，也就是誰都連不到，**apply 前一定要補**。

## 共用變數

每次開新的 shell 先跑這段。`<project>`、`<env>` 換成 tfvars 的值（`dev` 或 `sit`）。

```bash
export AWS_REGION=ap-northeast-1          # common.tf:24，aws_region 預設值；改過就跟著改
P=<project>                               # tfvars 的 project
E=<env>                                   # dev 或 sit
ssm() { aws ssm get-parameter --name "$1" --query Parameter.Value --output text; }

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
CLUSTER=$(ssm "/$P/$E/eks-cluster/cluster_name")      # 應該等於 "$P-$E"
NS=$(ssm "/$P/$E/eks-cluster/app_namespace")          # 預設 app
SERVICE_CIDR=$(ssm "/$P/$E/eks-cluster/service_cidr")
VPC_ID=$(ssm "/$P-shared/$E/infra/vpc_id")
APP_SG=$(ssm "/$P-shared/$E/infra/app_sg_id")
NODE_SG=$(ssm "/$P-shared/$E/infra/node_sg_id")
TG_ARN=$(ssm "/$P/$E/application/api_target_group_arn")
METRIC_NS=$(ssm "/$P/$E/application/worker_scaling_json" | jq -r .metric_namespace)   # <Project>/<env>，例如 Example/dev

# 只寫本機的 kubeconfig，不動叢集
aws eks update-kubeconfig --name "$CLUSTER" --region "$AWS_REGION"
```

名稱怎麼來的：

- 叢集名稱：`eks-cluster/cluster.tf:3` 的 `cluster_name = local.name_prefix`，`common.tf:47` 的 `name_prefix = "${var.project}-${var.env}"`。`iam/roles.tf:5` 用同一個規則組 Pod Identity 的 trust。
- SSM 前綴：`common.tf:50` 的 `ssm_prefix = "/${var.project}/${var.env}"`，`common.tf:54` 的 `shared_ssm_prefix = "/${var.project}-shared/${var.env}"`；key 名稱見 `eks-cluster/ssm-outputs.tf:6-16`、`application/ssm-outputs.tf:2-36`、`network/ssm-outputs.tf:6,13,14,25`。
- `app_namespace` 預設 `app`（`eks-cluster/variables.tf:52`）；ServiceAccount 預設 `api`、`worker`（`eks-cluster/variables.tf:63`、`:74`）。
- metric namespace：`application/environment.tf:16` 的 `"${title(var.project)}/${var.env}"`。

## 執行順序

順序照 `stacks.sh:8` 的 `ORDER` 與 README〈apply 順序〉〈部署〉。每個 stack 先跑 `--dry-run` 看一次指令。

| 階段 | 做什麼 | 在哪裡跑 | 做完接著驗 |
|---|---|---|---|
| 0 | 照 README〈複製出去之後要改什麼〉換掉佔位值；`network` 補 `k8s_api_sources`；`foundation` 的 `alarm_emails` 換成會收信的地址；`export TF_VAR_origin_verify_header_value=...`；api、worker、traffic-breaker 等映像推上 ECR | — | — |
| A | `./stacks.sh <env> containerimage apply`，依序 `foundation`、`network`、`database`、`iam`、`bridge`、`eks-cluster` | 任何能呼叫 AWS API 的地方 | 收到 SNS 訂閱確認信就點；S7、S8；第 3 項的 association 部分 |
| B | 把 secret 的值寫進 `foundation` 建的兩個 secret 容器（`foundation/secrets.tf:3-4`） | 同上 | — |
| C | `./stacks.sh <env> eks-addons apply` | VPC 或可連通的網路，身分是 `addons_apply_principal_arn` | 第 1 項的 system pool、S3、S6、第 10 項的 ClusterRole |
| D | `loadbalancer`、`agent`、`application` | 任何地方 | — |
| E | CI 部署 api、worker（README:305-313 的指令，release 名稱固定 `api`、`worker`） | VPC 或可連通的網路，身分是 `ci_deploy_principal_arn` | 第 1 項的 app pool、第 2–4 項、S4、S5、S10、第 10 項 |
| F | `operation`、`postdeploy` | 任何地方 | S9、第 5–7 項 |
| G | canary（第 9 項自己的步驟） | 混合 | 第 9 項 |
| H | no-NAT：另開一個 env，或在 dev 改 `nat_mode` 後重跑 A–F | 混合 | 第 8 項，接著重跑第 1–6 項 |
| X | 帳號 baseline 開 Transaction Search；`postdeploy` 的 `tracing_enabled = true` | 帳號 baseline 的 stack | X |

`application` 之後、`postdeploy` 之前一定要先部署 api 與 worker：`postdeploy` 的 log 告警要等 Container Insights 的 log group 存在（README:102）。

---

## 1. node 加入叢集

**前提**

- 階段 A–C 已 apply。
- `eks-addons` 的 `app_pool_cpu_limit`、`system_pool_cpu_limit` 沒設時是 100、16（`eks-addons/variables.tf:15`、`:26`）。
- `app` pool 要等階段 E 部署 api、worker 才會開 node；`system` pool 在階段 C 就該有 node，因為 LB Controller 與 KEDA 用 `karpenter.sh/nodepool=system` 加 toleration 排上去（`eks-addons/addons.tf:34-37`）。

**指令**

```bash
# 叢集：Auto Mode 開啟、沒有內建 NodePool、沒有 node role、只有 private endpoint
aws eks describe-cluster --name "$CLUSTER" --query 'cluster.{status:status,version:version,compute:computeConfig,public:resourcesVpcConfig.endpointPublicAccess,private:resourcesVpcConfig.endpointPrivateAccess,auth:accessConfig.authenticationMode}'

# node role 的 EC2 access entry 與 AmazonEKSAutoNodePolicy
NODE_ROLE_ARN="arn:aws:iam::$ACCOUNT:role/$P-$E-eks-node"
aws eks describe-access-entry --cluster-name "$CLUSTER" --principal-arn "$NODE_ROLE_ARN" --query 'accessEntry.type'
aws eks list-associated-access-policies --cluster-name "$CLUSTER" --principal-arn "$NODE_ROLE_ARN" \
  --query 'associatedAccessPolicies[].[policyArn,accessScope.type]' --output text

# NodeClass、NodePool、NodeClaim、node
kubectl get nodeclasses
kubectl get nodepools
kubectl get nodeclaims -o wide
kubectl get nodes -L karpenter.sh/nodepool,topology.kubernetes.io/zone

# system node 帶 CriticalAddonsOnly taint
kubectl get nodes -l karpenter.sh/nodepool=system -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.taints}{"\n"}{end}'

# LB Controller 與 KEDA 落在 system node
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller -o wide
kubectl -n keda get pods -o wide
```

名稱怎麼來的：node role `"${local.name_prefix}-eks-node"`（`iam/roles.tf:39`）；access entry `type = "EC2"` 與 `AmazonEKSAutoNodePolicy`（`eks-cluster/cluster.tf:24-28`）；NodeClass 與 NodePool 名稱 `app`、`system`（`eks-addons/addons.tf:14,21,28,29`，chart 用 key 當名稱：`modules/eks-addons/charts/auto-mode-nodes/templates/nodeclass.yaml:10`、`nodepool.yaml:6`）；taint `CriticalAddonsOnly:NoSchedule`（`eks-addons/addons.tf:8`）；LB Controller 的 label（`modules/eks-addons/main.tf:76`）；KEDA namespace `keda`（`modules/eks-addons/variables.tf:358`）。

**預期結果**

- `status` 是 `ACTIVE`；`compute.enabled` 是 `true`、`compute.nodePools` 是空的或沒有、`compute.nodeRoleArn` 沒有值；`public` 是 `false`、`private` 是 `true`；`auth` 是 `API`。
- access entry 的 type 是 `EC2`，policy 是 `arn:aws:eks::aws:cluster-access-policy/AmazonEKSAutoNodePolicy`，scope 是 `cluster`。
- `nodeclasses`、`nodepools` 各只有 `app`、`system` 兩個，`READY` 是 `True`；沒有 `general-purpose`。
- 階段 C 之後 `system` 至少一台 node `Ready`；階段 E 之後 `app` 至少一台 node `Ready`。
- `system` node 的 taint 有 `{"effect":"NoSchedule","key":"CriticalAddonsOnly"}`。
- LB Controller（2 個副本，`modules/eks-addons/variables.tf:32`）與 KEDA 的 pod 都 `Running`，`NODE` 是 `system` pool 的 node。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 2. DNS

**前提**

- 階段 E 完成（api、worker 已部署）。
- `network` 已有 `app` → `node` 的 TCP 53 與 UDP 53 規則（`network/security-groups.tf:53`、`:91-113`）。
- chart 的 NetworkPolicy 放行到 `dnsCidr` 的 UDP 與 TCP 53（`deploy/charts/app/templates/networkpolicy.yaml:30-37`）；`dnsCidr` 是 `service_cidr` 的 `.10/32`（`deploy/values-from-ssm.sh:126-130`、`:143`）。
- 系統元件的 NetworkPolicy 也放行到 `.10` 的 53（`modules/eks-addons/main.tf:57`、`:62`）。

**指令**

```bash
echo "$SERVICE_CIDR"     # DNS 應該是它的 .10

# NetworkPolicy 的 DNS 規則
kubectl -n "$NS" get networkpolicy api -o jsonpath='{.spec.egress[0]}{"\n"}'
kubectl -n "$NS" get networkpolicy worker -o jsonpath='{.spec.egress[0]}{"\n"}'

# pod 實際用的 resolver（需要映像裡有 cat）
kubectl -n "$NS" exec deploy/api -c api -- cat /etc/resolv.conf
kubectl -n "$NS" exec deploy/worker -c worker -- cat /etc/resolv.conf

# kube-dns Service（Auto Mode 的 DNS 實作方式未確認，可能沒有這個 Service）
kubectl -n kube-system get svc kube-dns -o wide

# SG 規則：app 出 53 到 node、node 收 app 的 53
aws ec2 describe-security-group-rules --filters Name=group-id,Values="$APP_SG" \
  --query 'SecurityGroupRules[?ToPort==`53`].[IsEgress,IpProtocol,ReferencedGroupInfo.GroupId]' --output table
aws ec2 describe-security-group-rules --filters Name=group-id,Values="$NODE_SG" \
  --query 'SecurityGroupRules[?ToPort==`53`].[IsEgress,IpProtocol,ReferencedGroupInfo.GroupId]' --output table
```

【寫入】在 api pod 加一個 ephemeral 除錯 container 測 UDP 與 TCP。它跟 api 共用 pod 的網路，所以 NetworkPolicy 與 Pod SG 跟 api 完全一樣。ephemeral container 加上去就拿不掉，要等 pod 換掉才會消失。

```bash
POD=$(kubectl -n "$NS" get pod -l app.kubernetes.io/instance=api -o jsonpath='{.items[0].metadata.name}')
DNS_IP=$(kubectl -n "$NS" exec "$POD" -c api -- awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)
kubectl -n "$NS" debug -it "$POD" --image=<debug-image> --target=api -- \
  sh -c "dig +notcp @$DNS_IP kubernetes.default.svc.cluster.local +short; \
         dig +tcp   @$DNS_IP kubernetes.default.svc.cluster.local +short; \
         dig +notcp @$DNS_IP sts.$AWS_REGION.amazonaws.com +short; \
         dig +tcp   @$DNS_IP sts.$AWS_REGION.amazonaws.com +short"
```

worker 照做一次，把 `api` 換成 `worker`。

名稱怎麼來的：NetworkPolicy 名稱是 release 名稱（`networkpolicy.yaml:7`）；pod label `app.kubernetes.io/instance=<release>`（`deploy/charts/app/templates/_helpers.tpl:9`）；container 名稱是 `component`（`deployment.yaml:30`）。

**預期結果**

- `egress[0]` 是 `ipBlock.cidr = <service CIDR 前三段>.10/32`，port UDP 53 與 TCP 53。
- `resolv.conf` 的 `nameserver` 是 `<service CIDR 前三段>.10`。
- `app` SG 有兩條 egress（tcp、udp 53）指到 `node` SG；`node` SG 有兩條 ingress 來自 `app` SG。
- 四個 `dig` 都回位址：UDP 與 TCP 都通，叢集內名稱與 AWS endpoint 都解得出來。
- 執行時一起記下：kube-dns Service 存不存在、ClusterIP 是多少（Auto Mode 的 DNS 跑在哪裡，repo 裡沒有確定的資料）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 3. Pod Identity

**前提**

- 階段 A–E 完成；階段 B 已把兩個 signing key 的值寫進 secret（名稱 `<project>-<env>/app-signing-public-key`、`<project>-<env>/app-signing-private-key`，`foundation/secrets.tf:3-4`），資料庫 secret 由 `database` 建。
- 應用程式的 AWS SDK 要支援 container credentials provider（`AWS_CONTAINER_CREDENTIALS_FULL_URI`，design §8.2）。

**指令**

```bash
# 5 個 association 與綁的 role
for id in $(aws eks list-pod-identity-associations --cluster-name "$CLUSTER" --query 'associations[].associationId' --output text); do
  aws eks describe-pod-identity-association --cluster-name "$CLUSTER" --association-id "$id" \
    --query 'association.[namespace,serviceAccount,roleArn]' --output text
done

# 哪些 pod 被注入了 Pod Identity 的環境變數
kubectl get pods -A -o json | jq -r '.items[]
  | select(any(.spec.containers[].env[]?; .name == "AWS_CONTAINER_CREDENTIALS_FULL_URI"))
  | "\(.metadata.namespace)/\(.metadata.name) sa=\(.spec.serviceAccountName)"'

# 每個 role 都真的換到憑證（最近 50 筆）
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleForPodIdentity \
  --max-results 50 --output json | jq -r '.Events[].CloudTrailEvent | fromjson
  | "\(.eventTime) \(.requestParameters.roleArn // .resources[0].ARN // "-") \(.errorCode // "OK")"'

# api、worker 讀 secret 成功
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=GetSecretValue \
  --max-results 50 --output json | jq -r '.Events[].CloudTrailEvent | fromjson
  | "\(.eventTime) \(.userIdentity.arn) \(.requestParameters.secretId) \(.errorCode // "OK")"'

# 元件的 log 沒有權限錯誤
kubectl -n kube-system logs deploy/aws-load-balancer-controller --since=1h | grep -iE 'accessdenied|unauthorized|no valid credential' || echo "LBC: 沒有權限錯誤"
kubectl -n keda logs deploy/keda-operator --since=1h | grep -iE 'accessdenied|unauthorized|no valid credential' || echo "KEDA: 沒有權限錯誤"
kubectl -n amazon-cloudwatch get ds,deploy
# 對上面列出的每個 DaemonSet／Deployment：
#   kubectl -n amazon-cloudwatch logs ds/<名稱> --since=1h | grep -iE 'accessdenied|unauthorized'
kubectl -n "$NS" logs deploy/api -c api --since=1h | grep -iE 'accessdenied|unable to locate credentials|credential' || echo "api: 沒有憑證錯誤"
kubectl -n "$NS" logs deploy/worker -c worker --since=1h | grep -iE 'accessdenied|unable to locate credentials|credential' || echo "worker: 沒有憑證錯誤"
```

名稱怎麼來的：

| namespace／ServiceAccount | role 名稱 | 出處 |
|---|---|---|
| `app`／`api` | `<project>-<env>-api-pod` | `eks-cluster/cluster.tf:14`；`iam/roles.tf:43` |
| `app`／`worker` | `<project>-<env>-worker-pod` | `eks-cluster/cluster.tf:15`；`iam/roles.tf:44` |
| `kube-system`／`aws-load-balancer-controller` | `<project>-<env>-lb-controller` | `eks-cluster/cluster.tf:7`；`iam/roles.tf:45` |
| `keda`／`keda-operator` | `<project>-<env>-keda` | `eks-cluster/cluster.tf:8`；`iam/roles.tf:46` |
| `amazon-cloudwatch`／`cloudwatch-agent` | `<project>-<env>-cloudwatch-agent` | `eks-cluster/cluster.tf:9`；`iam/roles.tf:47` |

`deploy/aws-load-balancer-controller` 是 release 名稱（`modules/eks-addons/main.tf:179`），chart 用它當 Deployment 名稱；`deploy/keda-operator` 是 KEDA chart 的命名（推測）。CloudWatch chart 的 DaemonSet 名稱 repo 裡沒有，所以先 `get` 再看。

**預期結果**

- association 剛好 5 個，namespace、ServiceAccount、role 跟上表一樣。
- 注入了環境變數的 pod：`app` 的 api 與 worker（sa `api`、`worker`）、`kube-system` 的 LB Controller、`keda` 的 operator、`amazon-cloudwatch` 用 sa `cloudwatch-agent` 的 pod（CloudWatch agent 與 Fluent Bit）。
- `AssumeRoleForPodIdentity` 對 5 個 role 都有 `OK`。
- `GetSecretValue` 的 `userIdentity.arn` 是 `arn:aws:sts::<account>:assumed-role/<project>-<env>-api-pod/...` 與 `...-worker-pod/...`，沒有 `errorCode`；worker 只讀資料庫 secret 與 public key，不讀 private key（`iam/policies.tf:115-121`）。
- 所有 log 的 grep 都沒有命中。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 4. TargetGroupBinding

**前提**

- 階段 A–E 完成。api 的 values 由 `values-from-ssm.sh` 產生，`targetGroupArn` 是 `application/api_target_group_arn`（`values-from-ssm.sh:140`）。
- target group 的 health check path 是 `/health`（`loadbalancer/alb.tf:27`）；chart 的 readiness probe 只是 TCP（`deployment.yaml:36-39`）。應用程式要回應 `/health`，不然 pod 是 Ready、target 卻是 unhealthy。

**指令**

```bash
aws elbv2 describe-target-groups --target-group-arns "$TG_ARN" \
  --query 'TargetGroups[].{name:TargetGroupName,type:TargetType,port:Port,hc:HealthCheckPath}'

kubectl -n "$NS" get targetgroupbindings.elbv2.k8s.aws api -o wide
kubectl -n "$NS" describe targetgroupbindings.elbv2.k8s.aws api | sed -n '/Events/,$p'

kubectl -n "$NS" get pods -l app.kubernetes.io/instance=api -o wide
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].[Target.Id,Target.Port,TargetHealth.State,TargetHealth.Reason]' --output table

# LB Controller 對 Terraform 建的 target group 能 RegisterTargets（§11 第 6 點）
kubectl -n kube-system logs deploy/aws-load-balancer-controller --since=2h | grep -iE 'registered targets|RegisterTargets|AccessDenied'

# Auto Mode 原生的 TargetGroupBinding 不該出現（API group 不同）
kubectl get targetgroupbindings.eks.amazonaws.com -A
```

【寫入】刪除 binding 後 target group 要還在。刪 stable 的 `api` 會讓 api 的流量中斷，所以：

- 有開 canary（第 9 項，`weight = 0`）時，刪 `api-canary` 的 binding，看 `<project>-<env>-alb-api-canary`；
- 沒開 canary 時，只在 dev、在可以中斷的時段刪 `api`。

```bash
REL=api-canary    # 或 api
kubectl -n "$NS" delete targetgroupbindings.elbv2.k8s.aws "$REL"
aws elbv2 describe-target-groups --names "$P-$E-alb-$REL" --query 'TargetGroups[].TargetGroupArn'
aws elbv2 describe-target-health --target-group-arn "$(aws elbv2 describe-target-groups --names "$P-$E-alb-$REL" --query 'TargetGroups[0].TargetGroupArn' --output text)" \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output text
# 復原：重跑 CI 的 helm upgrade --install（README:305-313，canary 用 README:342-343）
```

名稱怎麼來的：target group 名稱是 `"${var.name}-${each.key}"`（`modules/alb/main.tf:92`），ALB 名稱 `"${local.name_prefix}-alb"`（`loadbalancer/alb.tf:2`），key 是 `api` 與 `api-canary`（`loadbalancer/alb.tf:30-31`）；binding 名稱是 release 名稱（`targetgroupbinding.yaml:7`）；`app_port` 預設 8080（`application/variables.tf:4`）。

**預期結果**

- target group `<project>-<env>-alb-api`，type `ip`，port `8080`（或你設的 `app_port`），health check path `/health`。
- binding 存在，Events 沒有錯誤。
- `describe-target-health` 的 IP 跟 api pod 的 IP 一一對應，`healthy`。
- LB Controller 的 log 有註冊成功的訊息，沒有 `AccessDenied`。
- `targetgroupbindings.eks.amazonaws.com` 回 `No resources found`（或 `the server doesn't have a resource type`）。
- 刪除 binding 之後：target group 仍然存在，target 先 `draining` 後清空；重新部署後 target 回來。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 5. KEDA

**前提**

- 階段 A–F 完成。
- `application` 的副本數：`dev.tfvars` 是 `api_min_capacity = 1`、`api_max_capacity = 4`、`worker_min_capacity = 1`、`worker_max_capacity = 2`；`sit.tfvars` 沒設，用預設 2／10、2／6（`application/variables.tf:37,43,67,73`）。
- `stream_length_cap` 預設 100000（`application/variables.tf:10`），每個 worker 副本承擔 `stream_length_cap / 4` = 25000（`application/ssm-outputs.tf:29`）。
- api 的擴縮要有真實流量進 ALB（要帶 origin verify header），範本沒有附壓測工具，用團隊自己的。

**指令**

```bash
# KEDA metrics server 註冊成 external metrics API（KEDA 的命名，推測）
kubectl get apiservice v1beta1.external.metrics.k8s.io

kubectl -n "$NS" get scaledobject,triggerauthentication
kubectl -n "$NS" get hpa
kubectl -n "$NS" get hpa keda-hpa-api -o jsonpath='{.spec.behavior.scaleDown}{"\n"}'
kubectl -n "$NS" get hpa keda-hpa-worker -o jsonpath='{.spec.behavior.scaleDown}{"\n"}'
kubectl -n "$NS" describe hpa keda-hpa-api
kubectl -n "$NS" describe scaledobject api | sed -n '/Events/,$p'
kubectl -n "$NS" describe scaledobject worker | sed -n '/Events/,$p'
kubectl -n keda logs deploy/keda-operator --since=1h | grep -iE 'error|accessdenied' | tail -20

# api 用的 ALB 指標確實有資料
SCALING=$(ssm "/$P/$E/application/api_scaling_json")
aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name RequestCountPerTarget \
  --dimensions Name=TargetGroup,Value="$(jq -r .target_group_arn_suffix <<<"$SCALING")" Name=LoadBalancer,Value="$(jq -r .alb_arn_suffix <<<"$SCALING")" \
  --start-time "$(date -u -v-30M +%FT%TZ 2>/dev/null || date -u -d '-30 min' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" --period 60 --statistics Sum
```

【寫入】worker 的擴縮：灌一個假的 backlog 指標。值 60000 會讓 KEDA 要 `ceil(60000 / 25000) = 3` 個副本（受 `worker_max_capacity` 限制），也超過 `backlog_high` 的門檻 `stream_length_cap / 2 = 50000`，第 7 項可以一起看。真正的 worker 也在發這個指標，統計是 `Maximum`，所以會取到假的值。

```bash
for i in $(seq 1 12); do
  aws cloudwatch put-metric-data --namespace "$METRIC_NS" --metric-name StreamBacklogMax --dimensions Env="$E" --value 60000
  sleep 60
done &
kubectl -n "$NS" get deploy worker -w      # 看副本數變化；結束後 Ctrl-C
```

停止灌值之後記錄縮容的時間點：

```bash
kubectl -n "$NS" describe hpa keda-hpa-worker | sed -n '/Events/,$p'
```

api：在壓測期間跑 `kubectl -n "$NS" get hpa keda-hpa-api -w`，記下 CPU、RequestCountPerTarget、ActiveConnectionCount 三個 metric 的值與副本數。

名稱怎麼來的：ScaledObject 名稱是 release 名稱，TriggerAuthentication 是 `<release>-aws`（`scaledobject.yaml:6`、`:16`）；縮容規則 900／1／600（`deploy/charts/app/values.yaml:66-69`）；指標與維度（`scaledobject.yaml:40-87`）；worker 的維度 `Env=<env>`、metric `StreamBacklogMax`（`application/ssm-outputs.tf:31-34`）。HPA 名稱 `keda-hpa-<ScaledObject 名稱>` 是 KEDA 的命名，不在 repo 裡（推測）。

**預期結果**

- apiservice `AVAILABLE` 是 `True`。
- `scaledobject` 有 `api`、`worker`，`READY` 是 `True`；`triggerauthentication` 有 `api-aws`、`worker-aws`。
- HPA 的 `scaleDown` 是 `stabilizationWindowSeconds: 900`、`policies: [{type: Pods, value: 1, periodSeconds: 600}]`。
- `describe hpa keda-hpa-api` 列出 3 個 metric（cpu 與兩個 `s*-aws-cloudwatch`），值不是 `<unknown>`；api 的 `minReplicas`、`maxReplicas` 等於 tfvars。
- ScaledObject 沒有 `KEDAScalerFailed` 事件；KEDA operator 沒有 `AccessDenied`。
- `RequestCountPerTarget` 有資料點（有流量時）。
- 灌值後幾分鐘內 worker 副本數升到 `min(3, worker_max_capacity)`（dev 是 2）。
- 停止灌值後，第一次縮容發生在最後一次高值之後約 900 秒，之後每次減 1 個、間隔至少 600 秒，直到 `worker_min_capacity`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 6. CloudWatch 採集

**前提**

- 階段 C、E 完成。`eks-addons` 傳 `cloudwatch_observability = {}`（`eks-addons/addons.tf:64`），用 module 預設：chart `6.7.0`、namespace `amazon-cloudwatch`、Fluent Bit 開啟、Application Signals 關閉（`modules/eks-addons/variables.tf:387-391`）。
- DaemonSet 不設 placement，靠 chart 預設的 toleration 排到所有 node（`modules/eks-addons/main.tf:231-232`）。

**指令**

```bash
# DaemonSet 涵蓋每一台 node（兩個 pool）
kubectl get nodes --no-headers | wc -l
kubectl -n amazon-cloudwatch get ds        # 每個 DaemonSet 的 DESIRED、READY 應該等於 node 數
kubectl -n amazon-cloudwatch get pods -o wide

# log group
aws logs describe-log-groups --log-group-name-prefix "/aws/containerinsights/$CLUSTER/" \
  --query 'logGroups[].[logGroupName,retentionInDays]' --output text

# 工作負載指標（告警用的維度）
for w in api worker; do
  aws cloudwatch list-metrics --namespace ContainerInsights --metric-name replicas_ready \
    --dimensions Name=ClusterName,Value="$CLUSTER" Name=Namespace,Value="$NS" Name=PodName,Value="$w" --query 'Metrics[].Dimensions'
done

# node 指標涵蓋兩個 pool 的每台 node（node_cpu_utilization 是 Container Insights 的命名，推測）
aws cloudwatch list-metrics --namespace ContainerInsights --metric-name node_cpu_utilization \
  --dimensions Name=ClusterName,Value="$CLUSTER" --output json | jq -r '[.Metrics[].Dimensions[] | select(.Name=="NodeName") | .Value] | unique[]'
kubectl get nodes -L karpenter.sh/nodepool

# log 欄位符合 postdeploy 的 filter
aws logs filter-log-events --log-group-name "/aws/containerinsights/$CLUSTER/application" \
  --filter-pattern "{ \$.kubernetes.namespace_name = \"$NS\" && \$.kubernetes.container_name = \"api\" }" \
  --limit 3 --query 'events[].message' --output text
aws logs filter-log-events --log-group-name "/aws/containerinsights/$CLUSTER/application" \
  --filter-pattern "{ \$.kubernetes.namespace_name = \"$NS\" && \$.kubernetes.container_name = \"worker\" }" \
  --limit 3 --query 'events[].message' --output text

# system node 上的 log 也有進來
aws logs filter-log-events --log-group-name "/aws/containerinsights/$CLUSTER/application" \
  --filter-pattern '{ $.kubernetes.namespace_name = "kube-system" }' --limit 3 --query 'events[].message' --output text
```

用 filter 原樣測一筆真實訊息（唯讀）。從上面挑一筆應用程式印的 JSON log，把它的 `event` 改成 `record_enqueue_dropped` 再貼進去：

```bash
aws logs test-metric-filter \
  --filter-pattern "{ \$.kubernetes.namespace_name = \"$NS\" && \$.kubernetes.container_name = \"api\" && \$.log_processed.event = \"record_enqueue_dropped\" }" \
  --log-event-messages '<貼上改過的 message>'
```

名稱怎麼來的：application log group 是 `"/aws/containerinsights/${cluster_name}/application"`（`postdeploy/log-alarms.tf:5`）；filter 的欄位 `$.kubernetes.namespace_name`、`$.kubernetes.container_name`、`$.log_processed.event`（`postdeploy/log-alarms.tf:6`、`:10`）；工作負載指標維度 `ClusterName`、`Namespace`、`PodName`（`modules/eks-workload-alarms/main.tf:5-9`）。`performance`、`dataplane`、`host` 等其他 log group 是 Container Insights 的慣例，不在 repo 裡。

**預期結果**

- 每個 DaemonSet 的 `DESIRED` 與 `READY` 等於 node 數，`system` node 上也有 pod。
- `/aws/containerinsights/<cluster>/application` 存在，`retentionInDays` 是 `None`（永久，§11 第 17 點）。
- api、worker 的 `replicas_ready` 都查得到，維度剛好是 `ClusterName`、`Namespace`、`PodName`（PodName 是 Deployment 名稱 `api`、`worker`）。
- `node_cpu_utilization` 的 `NodeName` 清單涵蓋 `kubectl get nodes` 的每一台（含 `system` pool）。
- log 訊息是 JSON，有 `kubernetes.namespace_name`、`kubernetes.container_name`、`log`；應用程式印 JSON 時另外有 `log_processed`。
- `test-metric-filter` 回一筆 `matches`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 7. 告警

**前提**

- 階段 F 完成；`postdeploy` 的 `workload_alarms_enabled`、`stream_alarms_enabled`、`log_alarms_enabled` 都是 `true`（`postdeploy/envs/dev.tfvars:7-9`、`sit.tfvars:7-9`，預設是 `false`：`postdeploy/variables.tf:4,10,16`）。
- SNS 的 email 訂閱已確認。

**要確認的告警名稱**

| 類別 | 名稱 | 出處 |
|---|---|---|
| api 工作負載（8 條） | `<project>-<env>-api-replicas_below_desired`、`-api-crash_loop`、`-api-restarts`、`-api-pending`、`-api-oom_killed`、`-api-target_5xx_ratio`、`-api-latency_p95`、`-api-unhealthy_hosts` | `modules/eks-workload-alarms/main.tf:121` 是 `"${var.name}-${each.key}"`，**底線不轉換**；`var.name` 是 `"${local.name_prefix}-${k}"`（`postdeploy/workload-alarms.tf:19`）；key 見 `modules/eks-workload-alarms/main.tf:19-108` |
| worker 工作負載（5 條） | `<project>-<env>-worker-replicas_below_desired`、`-worker-crash_loop`、`-worker-restarts`、`-worker-pending`、`-worker-oom_killed` | 同上；worker 沒有 load balancer，ALB 的 3 條不建（`modules/eks-workload-alarms/main.tf:110-115`、`postdeploy/workload-alarms.tf:14`） |
| stream（2 條） | `<project>-<env>-stream-backlog-high`、`<project>-<env>-stream-no-consumers` | `postdeploy/stream-alarms.tf:48`；`modules/metric-alarm/main.tf:2` 把底線換成連字號 |
| api log（3 條） | `<project>-<env>-api-record-enqueue-dropped`、`-api-record-enqueue-failed`、`-api-rate-limiter-unavailable` | `postdeploy/log-alarms.tf:54`；`modules/log-metric-alarm/main.tf:7`，metric filter 用同一個名稱 |
| worker log（3 條） | `<project>-<env>-worker-record-write-failed`、`-worker-record-dead-lettered`、`-worker-record-consumer-stopped` | `postdeploy/log-alarms.tf:68`；同上 |

SNS topic 是 `<project>-<env>-alarms`（`foundation/alarms.tf:3`）。`restart_threshold` 預設 0（`modules/eks-workload-alarms/variables.tf:70`）。

**指令**

```bash
aws sns list-subscriptions-by-topic --topic-arn "arn:aws:sns:$AWS_REGION:$ACCOUNT:$P-$E-alarms" \
  --query 'Subscriptions[].[Protocol,Endpoint,SubscriptionArn]' --output table

aws cloudwatch describe-alarms --alarm-name-prefix "$P-$E-" \
  --query 'MetricAlarms[].[AlarmName,StateValue]' --output table

# 告警的維度跟實際的指標一致（notBreaching 的告警維度寫錯時會一直是 OK，看不出來）
for a in api-crash_loop api-pending api-restarts worker-crash_loop worker-pending worker-restarts; do
  dims=$(aws cloudwatch describe-alarms --alarm-names "$P-$E-$a" --query 'MetricAlarms[0].Dimensions' --output json)
  name=$(aws cloudwatch describe-alarms --alarm-names "$P-$E-$a" --query 'MetricAlarms[0].MetricName' --output text)
  echo "== $a ($name)"
  aws cloudwatch list-metrics --namespace ContainerInsights --metric-name "$name" \
    --dimensions "$(jq -r 'map("Name=\(.Name),Value=\(.Value)") | join(" ")' <<<"$dims")" --query 'length(Metrics)'
done

aws logs describe-metric-filters --log-group-name "/aws/containerinsights/$CLUSTER/application" \
  --query 'metricFilters[].[filterName,metricTransformations[0].metricNamespace,metricTransformations[0].metricName]' --output table
```

上面的 `--dimensions` 是一個參數帶多組值，如果 CLI 不接受，手動把 `Name=...,Value=...` 分開貼。

【寫入】通知路徑：每條告警都打一次（不要對第 9 項斷路器的告警做，會真的改 listener rule）。

```bash
aws cloudwatch set-alarm-state --alarm-name "$P-$E-api-crash_loop" --state-value ALARM --state-reason "runbook 通知測試"
```

狀態會在下一次評估時回到實際值。

【寫入】真實觸發，每一類至少一條：

```bash
# stream backlog_high：用第 5 項的 put-metric-data 迴圈，5 分鐘後應該 ALARM

# stream no_consumers 與工作負載告警：暫停 KEDA、把 worker 壓到 0 個副本（KEDA 的 paused-replicas 功能）
kubectl -n "$NS" annotate scaledobject worker autoscaling.keda.sh/paused-replicas="0" --overwrite
#   約 3 分鐘後 $P-$E-stream-no-consumers 應該 ALARM
#   復原：
kubectl -n "$NS" annotate scaledobject worker autoscaling.keda.sh/paused-replicas-

# log 告警：讓 worker 往 stdout 印一行事件（映像要有 sh）
kubectl -n "$NS" exec deploy/worker -c worker -- sh -c 'echo "{\"event\":\"record_dead_lettered\"}" > /proc/1/fd/1'
#   1–5 分鐘內 $METRIC_NS 的 RecordDeadLettered 有值，$P-$E-worker-record-dead-lettered 變 ALARM
```

crash_loop、oom_killed、pending、replicas_below_desired 的真實觸發要部署故意壞掉的映像（啟動就結束、吃光記憶體、拉不到的 tag）。只在 dev 做，做完用 CI 換回正常的 tag。

**預期結果**

- 訂閱的 `SubscriptionArn` 是完整 ARN，不是 `PendingConfirmation`。
- 上表 21 條都存在（同一個前綴下還會有其他 stack 的告警，例如 `<project>-<env>-alb-elb-5xx`，不算在內）。穩定狀態下都是 `OK`；`replicas_below_desired` 的 missing data 算 breaching，維度寫錯時會是 `ALARM`。
- 6 條維度檢查都回 `1` 以上。回 `0` 表示告警看的是不存在的指標。
- metric filter 6 條，namespace 是 `<Project>/<env>`。
- 每條 `set-alarm-state` 都收到 email。
- 真實觸發：`backlog-high`、`no-consumers`、`worker-record-dead-lettered` 變 `ALARM` 並收到 email；恢復後回 `OK`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註（列出只驗了通知路徑、沒有真實觸發的告警）______

## 8. no-NAT

**前提**

- `network` 與 `eks-addons` 的 tfvars 都設 `nat_mode = "none"`（`network/variables.tf:22`、`eks-addons/variables.tf:1`；`check-ssm-contract.sh` 會比對兩邊一致，README:271）。`network` 的 `bedrock_endpoints_enabled = true`（`network/envs/dev.tfvars`）。
- 建議另開一個 env 從頭 apply。在原本的 dev 從 `per_az` 改成 `none` 會刪掉 NAT gateway，執行中的 pod 會斷線。
- 跑 `eks-addons` 的 runner 要能抓 chart（README:124）；完全沒有對外連線時改用 `chart_repository_overrides`。
- 先知道的風險（見〈結論〉）：平台元件的映像來自公開 registry（推測）。`secretsmanager` endpoint 已補上，api 與 worker 讀 secret 應該要成功。

**指令**

```bash
aws ec2 describe-nat-gateways --filter Name=vpc-id,Values="$VPC_ID" Name=state,Values=available --query 'NatGateways[].NatGatewayId'

aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values="$VPC_ID" \
  --query 'VpcEndpoints[].[ServiceName,VpcEndpointType,State,PrivateDnsEnabled]' --output table

aws ec2 describe-route-tables --filters Name=vpc-id,Values="$VPC_ID" \
  --query 'RouteTables[].Routes[?DestinationCidrBlock==`0.0.0.0/0`].[GatewayId,NatGatewayId]' --output text

# system NetworkPolicy 的 AWS API 放行範圍改成 app subnet
kubectl -n keda get networkpolicy system-keda -o jsonpath='{.spec.egress}{"\n"}'
ssm "/$P-shared/$E/infra/app_subnet_cidrs"

# 拉映像失敗、起不來的 pod
kubectl get pods -A | grep -vE 'Running|Completed'
kubectl get events -A --field-selector type=Warning | grep -iE 'pull|timeout|dial tcp|i/o timeout' | tail -30
```

接著把第 1–6 項全部重跑一次，第 3 項的 `GetSecretValue` 一定要看。

名稱怎麼來的：no-NAT 時的 interface endpoint 清單（`network/endpoints.tf:5-8`）；endpoint 建在 app subnet（`network/endpoints.tf:10`）；NetworkPolicy 名稱 `system-<key>`，底線換連字號（`modules/eks-addons/charts/system-network-policy/templates/policies.yaml:6`），key 是 `keda`（`modules/eks-addons/main.tf:81`）；`aws_api_cidrs` 在 `none` 時是 app subnet CIDR（`eks-addons/addons.tf:44`）。

**預期結果**

- 沒有 `available` 的 NAT gateway；route table 沒有指到 `nat-` 的 `0.0.0.0/0`。
- interface endpoint：`eks`、`eks-auth`、`ec2`、`ecr.api`、`ecr.dkr`、`sts`、`elasticloadbalancing`、`logs`、`monitoring`、`bedrock`、`bedrock-agentcore`、`bedrock-runtime`（`com.amazonaws.<region>.<service>`），`available`、`PrivateDnsEnabled = true`；gateway endpoint `s3`。
- `system-keda` 的 443 egress 指到 app subnet CIDR，不是 `0.0.0.0/0`。
- 所有 pod `Running`，第 1–6 項全部通過。
- 不通過時，記下錯誤訊息裡連不到的 AWS host 與缺的 endpoint（如果平台元件的映像拉不到，會先看到公開 registry 的 host）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／缺的 endpoint 或映像 ______

## 9. canary

**前提**

- `containerimage` 的 `services` 有 `traffic-breaker`（`containerimage/envs/dev.tfvars:6`），斷路器的映像用 arm64 build 後推到 `<project>-traffic-breaker:<tag>`（README:334）。
- `loadbalancer/envs/<env>.tfvars` 加上：

  ```hcl
  canary = {
    weight  = 0
    breaker = { image_tag = "<tag>" }   # 不可以是 latest（loadbalancer/variables.tf:141）
  }
  ```

  `error_rate_percent`、`min_requests`、`min_healthy_hosts` 不寫時是 5、50、1（`loadbalancer/variables.tf:117-119`）。`<project>-<env>-alb-api-canary` 不能超過 32 字元（`loadbalancer/variables.tf:136`）。
- 已 `export TF_VAR_origin_verify_header_value`，再 `./stacks.sh <env> loadbalancer apply`。
- `weight = 0` 時 canary target group 是空的，`healthy-hosts` 告警會因為 missing data（breaching）馬上進 `ALARM`，會收到 email；Lambda 看到權重已經是 stable 就不動（`modules/lb-traffic-breaker/lambda/breaker.py:81-91`）。這是預期行為。

**名稱**

| 東西 | 名稱 | 出處 |
|---|---|---|
| target group | `<project>-<env>-alb-api`、`<project>-<env>-alb-api-canary` | `modules/alb/main.tf:92`、`loadbalancer/alb.tf:2,30-31` |
| 加權 rule | priority 10 `/api/stream`、20 `/api/quota`、30 `/api/admin` | `loadbalancer/alb.tf:6-10` |
| 斷路器告警（6 條） | `<project>-<env>-canary-api-stream-error-rate`、`-api-stream-healthy-hosts`、`-api-quota-error-rate`、`-api-quota-healthy-hosts`、`-api-admin-error-rate`、`-api-admin-healthy-hosts` | `modules/lb-traffic-breaker/main.tf:23-24`；`name = "${local.name_prefix}-canary"`（`loadbalancer/canary.tf:83`）；key 是 rule key 底線換連字號（`loadbalancer/canary.tf:11`） |
| Lambda 與 log group | `<project>-<env>-traffic-breaker`、`/aws/lambda/<project>-<env>-traffic-breaker` | `loadbalancer/canary.tf:6`、`modules/lambda-function/main.tf:2` |
| tag | key `traffic-breaker/tripped`，value 是觸發的告警名稱 | `modules/lb-traffic-breaker/lambda/breaker.py:15`、`handler.py:67` |
| SSM | `/<project>/<env>/loadbalancer/api_canary_target_group_arn` | `loadbalancer/ssm-outputs.tf:12-14` |
| canary release | `api-canary` | README:343 |

**指令**

```bash
aws elbv2 describe-target-groups --names "$P-$E-alb-api" "$P-$E-alb-api-canary" --query 'TargetGroups[].[TargetGroupName,TargetGroupArn]' --output text
ssm "/$P/$E/loadbalancer/api_canary_target_group_arn"
CANARY_TG=$(aws elbv2 describe-target-groups --names "$P-$E-alb-api-canary" --query 'TargetGroups[0].TargetGroupArn' --output text)

LB_ARN=$(aws elbv2 describe-load-balancers --names "$P-$E-alb" --query 'LoadBalancers[0].LoadBalancerArn' --output text)
show_rules() {
  for L in $(aws elbv2 describe-listeners --load-balancer-arn "$LB_ARN" --query 'Listeners[].ListenerArn' --output text); do
    aws elbv2 describe-rules --listener-arn "$L" \
      --query 'Rules[?Priority!=`default`].{p:Priority,path:Conditions[?Field==`path-pattern`]|[0].PathPatternConfig.Values,tg:Actions[?Type==`forward`]|[0].ForwardConfig.TargetGroups[].[TargetGroupArn,Weight]}' --output json
  done
}
show_rules

aws cloudwatch describe-alarms --alarm-name-prefix "$P-$E-canary-" --query 'MetricAlarms[].[AlarmName,StateValue]' --output table
```

步驟（照 README〈canary〉）：

1. `weight = 0` apply 之後跑上面的指令。
2. 【寫入】CI 部署 canary release（README:342-343）。然後：

   ```bash
   aws elbv2 describe-target-health --target-group-arn "$CANARY_TG" --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output text
   aws cloudwatch describe-alarms --alarm-name-prefix "$P-$E-canary-" --query 'MetricAlarms[?contains(AlarmName,`healthy-hosts`)].[AlarmName,StateValue]' --output text
   ```

3. 三條 `healthy-hosts` 都回到 `OK` 之後，tfvars 改 `weight = 10`，apply `loadbalancer`，再跑 `show_rules`。
4. 【寫入】觸發斷路器（只打一條）：

   ```bash
   aws cloudwatch set-alarm-state --alarm-name "$P-$E-canary-api-stream-error-rate" --state-value ALARM --state-reason "runbook 斷路器測試"
   sleep 30
   show_rules
   RULE_STREAM=$(for L in $(aws elbv2 describe-listeners --load-balancer-arn "$LB_ARN" --query 'Listeners[].ListenerArn' --output text); do
     aws elbv2 describe-rules --listener-arn "$L" --query 'Rules[?Priority==`10`].RuleArn' --output text; done)
   aws elbv2 describe-tags --resource-arns $RULE_STREAM --query 'TagDescriptions[].Tags[?Key==`traffic-breaker/tripped`]'
   aws logs filter-log-events --log-group-name "/aws/lambda/$P-$E-traffic-breaker" --filter-pattern '"tripped"' \
     --query 'events[].message' --output text
   ```

5. 觸發後的處理（README:348-353）：**先**把 tfvars 改回 `weight = 0` 並 apply `loadbalancer`。apply 前看 plan，記下它是否要拿掉 `traffic-breaker/tripped` tag。再 `helm uninstall api-canary -n "$NS"`（【寫入】）或修好重新部署。
6. 收尾：`canary = null` 並 apply，`<project>-<env>-alb-api-canary` 與 6 條告警都應該消失。

**預期結果**

- 步驟 1：兩個 target group 都在；SSM 有 canary ARN；priority 10、20、30 各有兩個 target group，stable 權重 100、canary 0；6 條告警都在。
- 步驟 2：canary target 是 `healthy`；`healthy-hosts` 告警回 `OK`。
- 步驟 3：三條 rule 都是 stable 90、canary 10。
- 步驟 4：只有 priority 10（`/api/stream`）變成 canary 0；**stable 維持 90**（Lambda 只把 canary 歸零、stable 保留原本大於 0 的權重：`breaker.py:109-112`；README〈canary〉也是這樣寫），20 與 30 不變。rule 有 tag `traffic-breaker/tripped = <project>-<env>-canary-api-stream-error-rate`。Lambda log 有 `tripped <rule ARN> to stable target group ...`。收到 email。
- 步驟 5：plan 把三條 rule 改成 100／0；apply 之後才處理 canary release。
- 步驟 6：canary 相關資源全部消失。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註（步驟 5 的 plan 有沒有拿掉 tag）______

## 10. CI 權限

**前提**

- 階段 A、C 完成；`eks-addons` 的 `aggregate_crd_roles = true`（`eks-addons/addons.tf:68`）。
- `eks-cluster` 的 `ci_deploy_principal_arn` 只拿到 `app_namespace` 的 `AmazonEKSEditPolicy`（`eks-cluster/cluster.tf:44-48`）。
- 驗證身分能 assume CI 的 role；不能的話整段在 CI runner 上跑。

**指令**

```bash
CI_ROLE=<ci_deploy_principal_arn>     # eks-cluster/envs/<env>.tfvars

aws eks list-associated-access-policies --cluster-name "$CLUSTER" --principal-arn "$CI_ROLE" \
  --query 'associatedAccessPolicies[].[policyArn,accessScope.type,join(`,`,accessScope.namespaces)]' --output text

# aggregate 進 edit 的 ClusterRole
kubectl get clusterrole eks-addons:targetgroupbindings-edit eks-addons:targetgroupbindings-view
kubectl get clusterrole edit -o json | jq -r '.rules[] | select(any(.apiGroups[]?; . == "elbv2.k8s.aws" or . == "keda.sh")) | "\(.apiGroups) \(.resources) \(.verbs)"'

# 用 CI 的身分問 API server（只寫本機 kubeconfig）
aws eks update-kubeconfig --name "$CLUSTER" --role-arn "$CI_ROLE" --alias "$CLUSTER-ci"
for r in targetgroupbindings.elbv2.k8s.aws scaledobjects.keda.sh triggerauthentications.keda.sh \
         networkpolicies.networking.k8s.io deployments.apps services serviceaccounts; do
  printf '%-40s %s\n' "$r" "$(kubectl --context "$CLUSTER-ci" auth can-i create "$r" -n "$NS")"
done
# 反向：其他 namespace 與叢集範圍不行
kubectl --context "$CLUSTER-ci" auth can-i create deployments.apps -n kube-system
kubectl --context "$CLUSTER-ci" auth can-i create namespaces
```

名稱怎麼來的：ClusterRole 名稱（`modules/eks-addons/charts/crd-role-aggregation/templates/target-group-bindings.yaml:7`、`:20`）；KEDA 的 aggregation 用 chart 的 `rbac.aggregateToDefaultRoles`（`modules/eks-addons/main.tf:226`）；chart 會建的四種資源（`targetgroupbinding.yaml:4-5`、`scaledobject.yaml:3-4,13-14`、`networkpolicy.yaml:4-5`）。

**預期結果**

- access policy 是 `AmazonEKSEditPolicy`，scope `namespace`，namespaces 是 `app`。
- 兩個 `eks-addons:targetgroupbindings-*` ClusterRole 存在；`edit` 的規則含 `elbv2.k8s.aws` 的 `targetgroupbindings` 與 `keda.sh` 的 `scaledobjects`、`triggerauthentications`。
- 7 個 `can-i create` 都是 `yes`。
- `kube-system` 與 `namespaces` 都是 `no`。
- CI 實際跑 README:305-313 的部署成功（階段 E）。
- 如果 CRD 三個是 `no` 而 `edit` 的規則有它們：表示 access policy 沒有吃到 RBAC aggregation（§11 第 15 點不成立），記在備註並開 issue。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

---

## design §11 的其他項目

### S1. node 與 pod 共用 app subnet、IP 預算（§11 第 1 點）

**前提**：階段 E 完成；最好在第 5 項 worker 擴到上限時再看一次。

**指令**

```bash
aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" Name=tag:eks-node,Values="$CLUSTER" \
  --query 'Subnets[].[SubnetId,AvailabilityZone,CidrBlock,AvailableIpAddressCount,Tags[?Key==`eks-pod`]|[0].Value]' --output table

# 每台 node 的 ENI 拿了幾個 /28 prefix、ENI 掛了哪些 SG
aws ec2 describe-network-interfaces --filters Name=vpc-id,Values="$VPC_ID" Name=group-id,Values="$APP_SG" \
  --query 'NetworkInterfaces[].[NetworkInterfaceId,SubnetId,length(Ipv4Prefixes || `[]`),length(PrivateIpAddresses)]' --output table
kubectl get nodes --no-headers | wc -l
```

名稱怎麼來的：app subnet 的 tag `eks-node`、`eks-pod`，值是 `name_prefix`（`network/vpc.tf:7`）；NodeClass 用同一組 tag 選 subnet（`eks-addons/addons.tf:5`、`:17`）；Pod SG 是 `app` SG（`eks-addons/addons.tf:18`）。

**預期結果**：每個 AZ 一個 /19 app subnet，兩個 tag 都等於叢集名稱；帶 `app` SG 的 ENI 存在（pod 的位址在這些 ENI 上）。記下 node 數、每台 node 的 prefix 數、剩餘 IP，跟 README〈IP 預算〉的估算（每台 node 1 + 4×16 個 IP）對照。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／node 數、每台 prefix 數、最少剩餘 IP ______

### S2. 兩個 load balancing controller 並存（§11 第 2 點）

**前提**：階段 C、E 完成。

**指令**

```bash
helm -n kube-system get values aws-load-balancer-controller --all | grep -E 'enableServiceMutatorWebhook|createIngressClassResource'
kubectl get ingressclass
kubectl get mutatingwebhookconfigurations -o name
kubectl -n "$NS" get svc api -o jsonpath='{.spec.type}{"\n"}'
aws elbv2 describe-load-balancers --query 'LoadBalancers[?VpcId==`'"$VPC_ID"'`].[LoadBalancerName,Type]' --output table
```

名稱怎麼來的：Auto Mode 時強制關掉的兩個值（`modules/eks-addons/main.tf:37-40`）；api 只有 ClusterIP Service（`deploy/charts/app/templates/service.yaml:10`）。

**預期結果**：兩個值都是 `false`；沒有 LB Controller 建的 IngressClass；api Service 是 `ClusterIP`；VPC 裡只有 `<project>-<env>-alb`，沒有 `k8s-` 開頭、由 controller 建的 load balancer。mutating webhook 清單記在備註，確認沒有 LB Controller 的 Service mutator。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

### S3. NodeClass／NodePool CRD 與 `amazon-vpc-cni` ConfigMap（§11 第 13、14 點）

**前提**：階段 C 完成。apply 有成功，大致就表示兩件事都沒問題；這裡留證據。

**指令**

```bash
kubectl get crd nodeclasses.eks.amazonaws.com nodepools.karpenter.sh nodeclaims.karpenter.sh
kubectl -n kube-system get configmap amazon-vpc-cni -o yaml | grep -E 'enable-network-policy-controller|meta.helm.sh/release-name|managed-by'
helm list -A
```

名稱怎麼來的：ConfigMap 名稱與內容（`modules/eks-addons/charts/system-network-policy/templates/vpc-cni-configmap.yaml:4-8`）；release 名稱 `auto-mode-nodes`、`system-network-policy`、`aws-load-balancer-controller`、`keda`、`amazon-cloudwatch-observability`、`crd-role-aggregation`、`app-namespaces`（`modules/eks-addons/main.tf:123,154,179,211,236,341,358`），CI 的 `api`、`worker`。

**預期結果**：三個 CRD 都在；ConfigMap 有 `enable-network-policy-controller: "true"`，由 Helm release `system-network-policy` 管（annotation `meta.helm.sh/release-name`，Helm 的慣例）；`helm list -A` 列出上面 7 個 release 加 `api`、`worker`，狀態都是 `deployed`。如果 `eks-addons` apply 時出現 ConfigMap 已存在的錯誤，第 14 點就是成立的風險，把錯誤訊息貼在備註。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

### S4. kubelet 探測與 `DefaultDeny` 下的系統元件（§11 第 3、4 點）

**前提**：階段 C、E 完成。兩個 NodeClass 都是 `DefaultDeny`（`eks-addons/addons.tf:19`、`:24`）。`network` 有 `node` → `app` 的 `app_port`（`network/security-groups.tf:52`）。

**指令**

```bash
kubectl get nodeclass app -o jsonpath='{.spec.networkPolicy}{"\n"}'
kubectl get nodeclass system -o jsonpath='{.spec.networkPolicy}{"\n"}'
kubectl get networkpolicy -A

# kubelet 探測：api pod Ready、沒有探測失敗
kubectl -n "$NS" get pods -l app.kubernetes.io/instance=api
kubectl -n "$NS" get events --field-selector reason=Unhealthy

# webhook 與 metrics
kubectl get apiservice v1beta1.external.metrics.k8s.io
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations
kubectl -n keda get pods
kubectl -n amazon-cloudwatch get pods
```

名稱怎麼來的：system NetworkPolicy `system-load-balancer-controller`（`kube-system`）、`system-keda`（`keda`）、`system-cloudwatch-observability`（`amazon-cloudwatch`）（`policies.yaml:6`、`modules/eks-addons/main.tf:72-104`）；app 的 `api`、`worker`。

**預期結果**：兩個 NodeClass 都是 `DefaultDeny`；上面 5 條 NetworkPolicy 都在；api pod `1/1 Ready`，沒有 `Unhealthy` 事件；apiservice `True`；第 4 項的 TargetGroupBinding 建得起來（LB Controller webhook 有通）；第 5 項的 ScaledObject 建得起來（KEDA webhook 有通）；`keda`、`amazon-cloudwatch` 的 pod 都 `Running`、沒有一直重啟。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

### S5. Pod Identity association 早於 namespace 與 ServiceAccount（§11 第 5 點）

**前提**：照正常順序 apply：`eks-cluster` 在階段 A 就建了 association，那時 `app`、`keda`、`amazon-cloudwatch` namespace 與 ServiceAccount 都還不存在。

**指令**：沿用第 3 項。另外記下 association 與 ServiceAccount 的建立時間：

```bash
for id in $(aws eks list-pod-identity-associations --cluster-name "$CLUSTER" --query 'associations[].associationId' --output text); do
  aws eks describe-pod-identity-association --cluster-name "$CLUSTER" --association-id "$id" --query 'association.[namespace,serviceAccount,createdAt]' --output text
done
kubectl get sa -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,CREATED:.metadata.creationTimestamp | grep -E 'api|worker|aws-load-balancer-controller|keda-operator|cloudwatch-agent'
```

**預期結果**：每個 association 的 `createdAt` 早於對應 ServiceAccount 的 `CREATED`，而第 3 項全部通過。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

### S6. helm provider 用 SSM 的 endpoint 與 CA（§11 第 7 點）

**前提**：階段 C。helm provider 的 `host`、`cluster_ca_certificate` 來自 SSM，token 用 `aws eks get-token`（`eks-addons/providers.tf:31-45`）。

**指令**：`./stacks.sh <env> eks-addons plan` 與 `apply` 的輸出本身就是證據，存下來。再比對 SSM 與 EKS 的值：

```bash
diff <(ssm "/$P/$E/eks-cluster/cluster_endpoint") <(aws eks describe-cluster --name "$CLUSTER" --query cluster.endpoint --output text) && echo endpoint 一致
diff <(ssm "/$P/$E/eks-cluster/cluster_ca_data") <(aws eks describe-cluster --name "$CLUSTER" --query cluster.certificateAuthority.data --output text) && echo CA 一致
```

**預期結果**：真實 plan 與 apply 都成功，沒有 TLS 或認證錯誤；兩個 `diff` 都一致。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

### S7. Kubernetes 版本（§11 第 11 點）

**前提**：階段 A；`kubernetes_version` 在 `eks-cluster/envs/<env>.tfvars:7`，placeholder 是 `1.36`。

**指令**

```bash
aws eks describe-cluster --name "$CLUSTER" --query 'cluster.[version,platformVersion]' --output text
aws eks describe-cluster-versions --cluster-versions "$(aws eks describe-cluster --name "$CLUSTER" --query cluster.version --output text)"
```

**預期結果**：版本等於 tfvars；`describe-cluster-versions` 顯示這個版本仍在標準支援（記下標準支援的結束日期）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／標準支援到 ______

### S8. secrets 加密的 KMS grant（§11 第 16 點）

**前提**：階段 A；`eks-cluster` 的 apply 身分要有 `kms:CreateGrant`、`kms:DescribeKey`。

**指令**

```bash
aws eks describe-cluster --name "$CLUSTER" --query 'cluster.encryptionConfig'
aws kms describe-key --key-id "alias/$CLUSTER-eks-secrets" --query 'KeyMetadata.[KeyId,KeyState]' --output text
aws kms list-grants --key-id "$(aws kms describe-key --key-id "alias/$CLUSTER-eks-secrets" --query KeyMetadata.KeyId --output text)" \
  --query 'Grants[].[GranteePrincipal,join(`,`,Operations)]' --output text
```

名稱怎麼來的：key 的 name 是 `"${local.cluster_name}-eks-secrets"`（`eks-cluster/cluster.tf:60`），alias 是 `"alias/${var.name}"`（`modules/kms-key/main.tf:70`）。

**預期結果**：`encryptionConfig` 的 resources 是 `secrets`，key 是這把 key；key `Enabled`；有一個 grantee 是 EKS 的 grant（principal 是叢集 role 或 EKS 服務，記下實際值）。apply 時沒有 `AccessDeniedException`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／grantee ______

### S9. application log group 的建立與 `postdeploy` 的順序（§11 第 17 點）

**前提**：階段 C、E 完成，**還沒** apply `postdeploy`。

**指令**

```bash
aws logs describe-log-groups --log-group-name-prefix "/aws/containerinsights/$CLUSTER/application" \
  --query 'logGroups[].[logGroupName,creationTime,retentionInDays]' --output text
```

然後 `./stacks.sh <env> postdeploy apply`。

**預期結果**：log group 已經存在、`retentionInDays` 是 `None`；`postdeploy` apply 成功，沒有 `ResourceNotFoundException`（metric filter 找不到 log group）。如果在 log group 出現前 apply 過，記下錯誤訊息，那就是 README:102 順序的證據。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

### S10. `tcp_keepalive_*` sysctl 與長連線擴縮（README〈已知限制〉、§8.2、§11 第 9 點）

**前提**：階段 E；api 有長連線（SSE）的流量時再看擴縮。

**指令**

```bash
kubectl get events -A --field-selector reason=SysctlForbidden
kubectl -n "$NS" exec deploy/api -c api -- cat /proc/sys/net/ipv4/tcp_keepalive_time /proc/sys/net/ipv4/tcp_keepalive_intvl /proc/sys/net/ipv4/tcp_keepalive_probes
```

SSE：壓測時同時記錄 `kubectl -n "$NS" get hpa keda-hpa-api -w` 與 `ActiveConnectionCount`（`AWS/ApplicationELB`，維度 `LoadBalancer=<alb_arn_suffix>`）。

名稱怎麼來的：三個 sysctl 與值 60、10、3（`deploy/charts/app/templates/deployment.yaml:22-28`）；ActiveConnectionCount 的 trigger（`scaledobject.yaml:56-70`）。

**預期結果**：沒有 `SysctlForbidden`；三個值是 `60`、`10`、`3`。SSE 部分沒有通過標準，記錄連線數上升到副本數增加的延遲、縮容時有沒有切斷連線，作為 §11 第 9 點的結論。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／擴縮延遲、縮容影響 ______

---

## X. X-Ray Transaction Search（`modules/xray-transaction-search`）

**前提**

- 帳號 baseline（不是 example3 的 stack）呼叫這個 module 一次，`indexing_percentage` 預設 1、`resource_policy_name` 預設 `xray-transaction-search`（`modules/xray-transaction-search/variables.tf:3`、`:14`）。module README:5 規定每個帳號、每個 region 只由一處呼叫。
- 部署者要有 module README:34 列的六個權限。
- 要有 span 進來：`agent` 的 Runtime 開了追蹤，`postdeploy` 的 `tracing_enabled = true`（`postdeploy/envs/dev.tfvars:10`）把 Runtime 與 Memory 的 `TRACES` 送進 X-Ray（`postdeploy/tracing.tf:4-9`），之後實際呼叫一次 Runtime。

**指令**

```bash
# 1. policy 生效
aws logs describe-resource-policies --query 'resourcePolicies[?policyName==`xray-transaction-search`].policyDocument' --output text | jq .

# 2. destination 變成 ACTIVE（開啟後約 10 分鐘）
aws xray get-trace-segment-destination
aws xray get-indexing-rules --query 'IndexingRules[?Name==`Default`]'

# 3. span 進到 aws/spans
aws logs describe-log-groups --log-group-name-prefix aws/spans --query 'logGroups[].logGroupName' --output text
aws logs describe-log-streams --log-group-name aws/spans --order-by LastEventTime --descending --max-items 3 \
  --query 'logStreams[].[logStreamName,lastEventTimestamp]' --output text

# trace delivery 有建起來
aws logs describe-delivery-sources --query "deliverySources[?starts_with(name, '$P-$E-traces')].[name,logType]" --output text
```

**預期結果**

- policy 的 principal 是 `xray.amazonaws.com`，action `logs:PutLogEvents`，resource 是 `aws/spans` 與 `/aws/application-signals/data`，條件綁本帳號與本 region（`modules/xray-transaction-search/main.tf:12-31`）。
- `Destination` 是 `CloudWatchLogs`、`Status` 是 `ACTIVE`。
- `Default` rule 的比例等於 `indexing_percentage`。
- `aws/spans` 存在，呼叫 Runtime 後幾分鐘內有新的 `lastEventTimestamp`。
- delivery source 有 `<project>-<env>-traces-runtime-<runtime>` 與 `<project>-<env>-traces-memory`，`logType` 是 `TRACES`（名稱來自 `postdeploy/tracing.tf:5-6,19` 與 `modules/log-delivery/main.tf:17`）。

**destroy 的注意事項**（module README:32）：destroy 不會關掉 Transaction Search，只會刪掉 resource policy，之後 span 會無聲遺失。要拿掉時，先跑：

```bash
aws xray update-trace-segment-destination --destination XRay     # 【寫入】
```

再 destroy。要驗證這件事，只在可以丟棄的帳號做：照順序執行後，`get-trace-segment-destination` 應該是 `XRay`，`describe-resource-policies` 查不到 `xray-transaction-search`。正式帳號只要確認 destroy 的流程文件有寫這一步。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／ACTIVE 花了幾分鐘 ______

---

## 結果怎麼回寫

執行人是負責 apply 的專案 app team 成員；回寫分三處，都用 PR：

| 回寫到哪裡 | 誰改 | 怎麼改 | 誰審 |
|---|---|---|---|
| 本 runbook 的「結果紀錄」 | 執行人 | 每一項填完那一行；不通過的附 issue 連結 | 跟下一列同一個 PR |
| `templates/example3/infra/README.md`〈雲端整合待驗證〉表 | 執行人 | 表格加一欄「結果」，寫 `通過（YYYY-MM-DD，dev）` 或 `不通過：<一句話>（#issue）`。10 項都通過時，比照〈靜態驗證通過（2026-10-23）〉另開一節〈雲端驗證通過（日期）〉把表搬過去；〈已知限制〉裡已經確認的條目刪掉；檔案開頭的狀態句（README:3）改成實際狀態 | platform team ＋ 專案代表（`/templates/` 的 CODEOWNERS） |
| `docs/design/v4/design-docs.md` §11 | platform team | 每一點後面加 `→ 已確認（YYYY-MM-DD，runbook S<n> 或第 <n> 項）`，或 `→ 不成立：<實際行為>，改法見 #issue`。不成立而要改設計的，在文末加一個附錄記下決定 | platform team |
| `modules/xray-transaction-search/README.md:35` 與其他 module README 的「還沒在真實帳號 apply 過」 | platform team | X 通過後改成實際驗證的日期與帳號類型 | platform team |

不通過的處理：

- 問題在 module（例如 `eks-addons`、`lb-traffic-breaker`）：照 `docs/guides/team-roles.md`〈交接點〉在本 repo 開 issue 給 platform team，附指令輸出。
- 問題在範本的 stack 或 chart：開 issue 並標 `templates/example3`，修正走一般的範本改版 PR。
- 同一項修好後重跑，結果紀錄寫新的一行，舊的不刪。
