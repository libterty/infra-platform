# eks-iam-policies

輸出 EKS 常用 controller 的官方 IAM policy JSON：AWS Load Balancer Controller、Karpenter controller、Argo Rollouts（CloudWatch analysis 用）、KEDA（CloudWatch scaler 用）。不建任何資源。

## 為什麼是一個沒有資源的 module

IAM stack 要在 `eks-cluster` 之前建好（設計文件 D15、J14）；呼叫 `eks-addons` 又要先設好 helm provider，所以 policy 不能放在 `eks-addons` 的輸出。這個 module 讓不用範本的人也拿得到跟 chart 版本對得上的 policy。

role 仍由呼叫端用 [`iam-role`](../iam-role/README.md) 建，這個 module 只提供 policy 內容。

## 用法

```hcl
module "eks_policies" {
  source = "git::https://github.com/<org>/<repo>.git//modules/eks-iam-policies?ref=eks-iam-policies-v0.1.0"

  cluster_name = "alpha-dev"
  region       = "ap-northeast-1"
  account_id   = "111111111111"

  karpenter = {
    node_role_arn           = module.node_role.arn
    interruption_queue_name = "alpha-dev-karpenter"
  }
}

module "lb_controller_role" {
  source = "git::https://github.com/<org>/<repo>.git//modules/iam-role?ref=iam-role-v0.3.0"

  name = "alpha-dev-lb-controller"

  trust = {
    service_principals = ["pods.eks.amazonaws.com"]
    tag_session        = true
  }

  inline_policies = {
    lb-controller = module.eks_policies.load_balancer_controller_policy_json
  }
}
```

Karpenter、Argo Rollouts、KEDA 的 role 寫法相同，分別用 `karpenter_controller_policy_json`、`argo_rollouts_cloudwatch_policy_json` 與 `keda_cloudwatch_policy_json`。完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

四個 policy 都通過 `iam-role` 的 `inline_policies` 檢查（沒有 `*` 或 `service:*` 的 Allow 動作、沒有 `NotAction`、`NotResource`）。

## Policy 來源

| Policy | 版本 | 來源 | 取得時的 tag 與 commit |
|---|---|---|---|
| LB Controller | `3.6.1`（預設）、`3.6.0` | [`docs/install/iam_policy.json`](https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.6.1/docs/install/iam_policy.json) | 預設 `3.6.1`：tag `v3.6.1`，commit `cce96f2c8ae138e85ead0e5efa0d6ad0bde7b11c`；`3.6.0`：tag `v3.6.0`，commit `267b5458b4c4c3066d47673a36dda275af07a6d6` |
| Karpenter controller | `1.15.0` | [`cloudformation.yaml`](https://raw.githubusercontent.com/aws/karpenter-provider-aws/v1.15.0/website/content/en/docs/getting-started/getting-started-with-karpenter/cloudformation.yaml) | tag `v1.15.0`，commit `b2896451034b61e8641b8b891e4a0f10d905608f` |
| Argo Rollouts CloudWatch | 無版本 | 自己寫，只有 `cloudwatch:GetMetricData` | 不適用 |
| KEDA CloudWatch | 無版本 | 自己寫，只有 `cloudwatch:GetMetricData`（KEDA `aws-cloudwatch` scaler 需要） | 不適用 |

### LB Controller

- 官方檔案原樣存在 [`policies/aws-load-balancer-controller/v3.6.1.json`](./policies/aws-load-balancer-controller/v3.6.1.json)（預設）與 [`v3.6.0.json`](./policies/aws-load-balancer-controller/v3.6.0.json)，沒有手改。`3.6.1` 與 `3.6.0` 的 policy 內容逐字相同（和官方 `v3.6.1` 的 `iam_policy.json` 做 diff 沒有差異），保留 `3.6.0` 是讓已經固定這個版本的呼叫端不會壞掉。輸出是 `jsonencode(jsondecode(file(...)))`，只去掉空白，內容不變。
- 官方檔案的 ARN 寫死 `arn:aws:`（13 處）。照官方，所以 `partition` 對這個 policy 沒有作用；在 `aws-cn`、`aws-us-gov` 使用前要自己確認。
- `cluster_name`、`region`、`account_id` 對這個 policy 也沒有作用：官方 policy 不依叢集而變。

### Karpenter controller

- `v1.15.0` tag 裡沒有 `v1.15/` 版本目錄，檔案在 `docs/` 目錄下（該 tag 的 `docs/` 就是 v1.15.0 發佈時的文件）。原始 yaml 存在 [`policies/karpenter/v1.15.0/cloudformation.yaml`](./policies/karpenter/v1.15.0/cloudformation.yaml) 供審查。
- 轉換方式：把 CloudFormation 裡六個 controller managed policy 的 statement 依原順序轉成 `locals.tf` 的 HCL 物件，合成一份 policy 文件，共 18 段，沒有刪減或改寫權限：

  | CloudFormation 的 policy | statement 數 |
  |---|---|
  | `NodeLifecyclePolicy` | 6 |
  | `IAMIntegrationPolicy` | 4 |
  | `EKSIntegrationPolicy` | 1 |
  | `InterruptionPolicy` | 1 |
  | `ZonalShiftPolicy` | 1 |
  | `ResourceDiscoveryPolicy` | 5 |

- 變數替換：`${AWS::Partition}` → `partition`、`${AWS::Region}` → `region`、`${AWS::AccountId}` → `account_id`、`${ClusterName}` → `cluster_name`、`${KarpenterNodeRole.Arn}` → `karpenter.node_role_arn`、`${KarpenterInterruptionQueue.Arn}` → `arn:<partition>:sqs:<region>:<account_id>:<interruption_queue_name>`。
- 不收 CloudFormation 裡的 node role、SQS queue、queue policy 與 EventBridge rule；這些由 `eks-cluster` 與 `iam` stack 建。
- `iam:PassRole` 只限 `node_role_arn`，並保留官方的 `iam:PassedToService` 條件。SQS 動作（`DeleteMessage`、`GetQueueUrl`、`ReceiveMessage`）只限 queue ARN。
- 官方的 `iam:PassedToService` 條件含 `ec2.amazonaws.com.cn`，照官方保留。
- 沒有逐字比對轉換結果與 yaml 的測試；測試檢查 statement 數、Sid 清單、`iam:PassRole`、SQS、`eks:DescribeCluster` 的範圍與佔位符是否替換乾淨。轉換是人工做的，升版時要逐段對照 yaml。

### KEDA

- 只有 `cloudwatch:GetMetricData`，`Resource` 為 `"*"`，內容與 Argo Rollouts 的 policy 相同，理由見下一節。分成兩個輸出是因為兩者掛在不同的 role（不同 ServiceAccount）。

### Argo Rollouts

- 只有 `cloudwatch:GetMetricData`，`Resource` 為 `"*"`。
- 依據：[CloudWatch permissions reference](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/permissions-reference-cw.html) 寫明 CloudWatch 的動作要「specify a wildcard character (*) as the resource value」。
- 未確認：AWS 的 [service reference](https://servicereference.us-east-1.amazonaws.com/v1/cloudwatch/cloudwatch.json) 把 `GetMetricData` 列了一個 `dataset` 資源型別（`arn:<partition>:cloudwatch:<region>:<account>:dataset/<id>`），用在 metrics dataset 這類較新的功能；一般的 metric 查詢沒有對應的資源 ARN，所以沿用 `"*"`。如果日後要用 dataset，要重新檢視。

## R5：inline policy 長度

IAM 對一個 role 的 inline policy 總和限制是 10,240 字元，計算時不含空白。來源：[IAM and AWS STS quotas](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_iam-quotas.html)（「Role policy size can't exceed 10,240 characters」「IAM doesn't count white space」）。

`policy_sizes` 輸出每份 JSON 去空白後的字元數。實測（`cluster_name = "alpha-dev"`、`region = "ap-northeast-1"`、`account_id = "111111111111"`）：

| Policy | 字元數 | 占 10,240 的比例 |
|---|---|---|
| `load_balancer_controller` | 5,196 | 51% |
| `karpenter_controller` | 6,154 | 60% |
| `argo_rollouts_cloudwatch` | 110 | 1% |
| `keda_cloudwatch` | 110 | 1% |

結論：

- 各自放在自己的 role 沒有問題，LB Controller 與 Karpenter 都在上限以內。設計文件 R5 擔心的「LB Controller 單獨超過上限」沒有發生。
- 兩份放同一個 role 會超過（LB Controller 加 Karpenter 是 11,350）。每個 controller 一個 role，不要合併。
- `karpenter_controller` 的長度會隨 `cluster_name`、`node_role_arn`、`interruption_queue_name` 變動（名稱越長越大），名稱接近上限時要重新看 `policy_sizes`。
- 一個 role 要放多份 policy 時，把 `policy_sizes` 相關項目加總，超過 10,240 就改成每個 policy 一個 role。`iam-role-policy` 附加的仍是 inline policy，總和還是算在同一個 role 上，所以設計文件 R5 寫的「拆成 `iam-role-policy` 的多份 policy」解決不了總和限制。
- 這些數字是在本機用只有輸出的 root 算出的，沒有送進 AWS 驗證。

## 升版流程

### LB Controller

1. 下載新版官方 `iam_policy.json`（URL 把 tag 換成新版），原樣存成 `policies/aws-load-balancer-controller/v<版本>.json`，不要手改。
2. 在 `locals.tf` 的 `load_balancer_controller_policies` 加一筆 `"<版本>" = file(...)`。允許清單就是這個 map 的 key，不用另外改 validation。
3. 更新 `tests/lb-controller.tftest.hcl`、`tests/sizes.tftest.hcl` 裡的檔案路徑，補新版本的測試；重新量 `policy_sizes` 並更新本 README 的 R5 表格。
4. 更新本 README 的來源表（tag、commit）與 `CHANGELOG.md`。

### Karpenter

1. 下載新版 tag 的 `cloudformation.yaml`，存成 `policies/karpenter/v<版本>/cloudformation.yaml`。
2. 逐段對照新舊 yaml 的 controller policy 差異，在 `locals.tf` 新增 `karpenter_v<版本>_statements`，並把版本加進 `karpenter_supported_versions` 與 `karpenter_controller_policy_json` 裡的版本對照表。兩處要一起改；只改對照表會被 validation 擋下，只改清單則會在 plan 時查不到對照表的 key 而失敗。
3. 補新版本的測試（statement 數、Sid、`iam:PassRole`、SQS 範圍），更新 `policy_sizes`、來源表與 `CHANGELOG.md`。

## 限制

- `versions.tf` 宣告了 `aws` provider，雖然這個 module 沒有用到。原因：`scripts/validate.sh` 的 S1 要求每個測試檔有 `mock_provider "aws"`，而 Terraform 在 module 沒宣告 `aws` 時，對這個 mock 報 `unknown provider registry.terraform.io/hashicorp/aws`。呼叫端不需要設定 provider，也不會用到憑證。
- 只接受 module 附的版本；沒附的版本要先走升版流程。
- Karpenter 的轉換是人工做的，沒有程式比對 yaml；LB Controller 則是原檔。
- 不檢查 `node_role_arn` 的帳號是否等於 `account_id`。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `cluster_name` | `string` | 無 | 是 | EKS cluster 名稱，用在 ARN 與 Karpenter policy 的 cluster tag 條件。1–100 字元，限英數字、`-`、`_`，首字元須為英數字。 |
| `region` | `string` | 無 | 是 | cluster 所在 region，例如 `ap-northeast-1`。 |
| `account_id` | `string` | 無 | 是 | cluster 所在的 12 位數 AWS 帳號 ID。 |
| `partition` | `string` | `"aws"` | 否 | 這個 module 組出的 ARN 用的 AWS partition：`aws`、`aws-cn` 或 `aws-us-gov`。LB Controller policy 是官方檔案，不受影響。 |
| `load_balancer_controller_version` | `string` | `"3.6.1"` | 否 | 要輸出哪個版本的 AWS Load Balancer Controller 官方 IAM policy。只接受 module 在 `policies/aws-load-balancer-controller/` 附的版本（目前是 `3.6.0`、`3.6.1`）。 |
| `karpenter` | `object` | `null` | 否 | Karpenter controller policy 的設定；`null` 時不輸出 Karpenter policy。欄位：`version`（預設 `1.15.0`，只接受 `local.karpenter_supported_versions` 列的版本，目前只有 `1.15.0`）、`node_role_arn`（controller 唯一能 pass 給 EC2 的 role，必須是不含萬用字元的 IAM role ARN）、`interruption_queue_name`（controller 可讀的 SQS queue，1–80 字元，限英數字、`-`、`_`）。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `load_balancer_controller_policy_json` | 所選版本的 AWS Load Balancer Controller 官方 IAM policy，去空白的 JSON 字串。 |
| `karpenter_controller_policy_json` | 所選版本的 Karpenter controller IAM policy（官方各份 controller policy 併成一份），去空白的 JSON 字串。`karpenter` 為 `null` 時是 `null`。 |
| `argo_rollouts_cloudwatch_policy_json` | Argo Rollouts 做 CloudWatch 指標分析用的 policy（`cloudwatch:GetMetricData`），去空白的 JSON 字串。 |
| `keda_cloudwatch_policy_json` | KEDA `aws-cloudwatch` scaler 用的 policy（`cloudwatch:GetMetricData`），去空白的 JSON 字串。 |
| `policy_sizes` | 各 policy JSON 去空白後的字元數（`map(number)`），IAM 就是這樣計入 role inline policy 的 10,240 字元上限。key：`load_balancer_controller`、`argo_rollouts_cloudwatch`、`keda_cloudwatch`，`karpenter` 有給時加 `karpenter_controller`。放在同一個 role 的 policy 要把大小加總。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/eks-iam-policies
```
