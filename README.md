# infra-platform

[![CI](https://github.com/libterty/infra-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/libterty/infra-platform/actions/workflows/ci.yml) [![Registry](https://img.shields.io/badge/registry-app.terraform.io%2Flibterty-7B42BC?logo=terraform&logoColor=white)](https://app.terraform.io/app/libterty/registry/private/modules)

這是 Terraform private registry 的範例 repo。共用 module 都放在這個 monorepo，用 Git tag 標版本，透過 HCP Terraform private registry 發布。各專案用版本範圍引用同一份 module，不用每個專案各寫一套。

## module

共 55 個 module，tag 格式是 `<module>-v<MAJOR>.<MINOR>.<PATCH>`。

| 分類             | module                        | 用途                                                                               | 最新版 |
| ---------------- | ----------------------------- | ---------------------------------------------------------------------------------- | --- |
| 網路與入口       | `vpc`                       | VPC、分層 subnet、NAT、gateway endpoint、flow log                                  | [![vpc](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=vpc-v*&label=)](https://github.com/libterty/infra-platform/releases?q=vpc-v) |
| 網路與入口       | `vpc-interface-endpoints`   | interface endpoint（PrivateLink）與共用的 SG                                       | [![vpc-interface-endpoints](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=vpc-interface-endpoints-v*&label=)](https://github.com/libterty/infra-platform/releases?q=vpc-interface-endpoints-v) |
| 網路與入口       | `alb`                       | ALB、listener、target group 與 listener rule（含加權 forward）、ELB 5xx 告警                                                        | [![alb](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=alb-v*&label=)](https://github.com/libterty/infra-platform/releases?q=alb-v) |
| 網路與入口 | `waf-web-acl` | REGIONAL WAF web ACL：kill switch、rate limit、managed rule、body size、log 遮蔽 | [![waf-web-acl](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=waf-web-acl-v*&label=)](https://github.com/libterty/infra-platform/releases?q=waf-web-acl-v) |
| 網路與入口 | `vpc-peering` | VPC peering 請求端與路由 | [![vpc-peering](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=vpc-peering-v*&label=)](https://github.com/libterty/infra-platform/releases?q=vpc-peering-v) |
| 網路與入口 | `nlb` | NLB、TCP／TLS／UDP listener、加權 target group（金絲雀）、健康主機告警 | [![nlb](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=nlb-v*&label=)](https://github.com/libterty/infra-platform/releases?q=nlb-v) |
| 網路與入口 | `lb-traffic-breaker` | ALB／NLB 斷路器：canary 出錯時由 alarm 觸發 Lambda，把權重切回舊系統 | [![lb-traffic-breaker](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=lb-traffic-breaker-v*&label=)](https://github.com/libterty/infra-platform/releases?q=lb-traffic-breaker-v) |
| 網路與入口 | `vpn-site-to-site` | Site-to-Site VPN：customer gateway 加 VPN 連線，終點是自建 VGW 或既有 TGW 擇一；PSK 固定存 Secrets Manager、兩條 tunnel 的 log 寫進 CMK log group、IKE 只收 ikev2 與強演算法 | [![vpn-site-to-site](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=vpn-site-to-site-v*&label=)](https://github.com/libterty/infra-platform/releases?q=vpn-site-to-site-v) |
| 資料             | `rds`                       | RDS、Aurora、Aurora Serverless v2，可選 RDS Proxy                                  | [![rds](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=rds-v*&label=)](https://github.com/libterty/infra-platform/releases?q=rds-v) |
| 資料 | `elasticache-redis` | ElastiCache Redis（cluster mode）：固定加密與 multi-AZ、可選 shard autoscaling、告警 | [![elasticache-redis](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=elasticache-redis-v*&label=)](https://github.com/libterty/infra-platform/releases?q=elasticache-redis-v) |
| 資料平台 | `dynamodb-table` | DynamoDB table：on-demand 或 provisioned、可選 GSI、TTL、Streams；固定 KMS 加密、PITR 與刪除保護 | [![dynamodb-table](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=dynamodb-table-v*&label=)](https://github.com/libterty/infra-platform/releases?q=dynamodb-table-v) |
| 資料平台 | `kinesis-stream` | Kinesis Data Stream：on-demand 或 provisioned，固定 KMS 加密 | [![kinesis-stream](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=kinesis-stream-v*&label=)](https://github.com/libterty/infra-platform/releases?q=kinesis-stream-v) |
| 資料平台 | `glue-catalog` | Glue Data Catalog 的 database：多個 database，名稱與 `location_uri` 在 validation 檢查 | [![glue-catalog](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=glue-catalog-v*&label=)](https://github.com/libterty/infra-platform/releases?q=glue-catalog-v) |
| 資料平台 | `glue-catalog-encryption` | 帳號層：用客戶管理的 KMS key 加密 Glue Data Catalog 與 connection 密碼（每個帳號、每個 region 只能由一處呼叫） | [![glue-catalog-encryption](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=glue-catalog-encryption-v*&label=)](https://github.com/libterty/infra-platform/releases?q=glue-catalog-encryption-v) |
| 資料平台 | `glue-etl` | Glue ETL：security configuration、crawler、Spark job（含 Flex）、trigger、workflow，可選 S3 事件經 EventBridge 批次觸發 workflow | [![glue-etl](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=glue-etl-v*&label=)](https://github.com/libterty/infra-platform/releases?q=glue-etl-v) |
| 資料平台 | `opensearch-domain` | VPC 內的 OpenSearch domain：hot、可選 dedicated master／UltraWarm／cold，固定加密與 FGAC，master 帳密從 Secrets Manager 讀 | [![opensearch-domain](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=opensearch-domain-v*&label=)](https://github.com/libterty/infra-platform/releases?q=opensearch-domain-v) |
| 資料平台 | `opensearch-config` | OpenSearch domain 內部設定（opensearch provider）：ISM policy（hot、UltraWarm、cold、刪除）、寫入用 FGAC role 與 mapping、index template | [![opensearch-config](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=opensearch-config-v*&label=)](https://github.com/libterty/infra-platform/releases?q=opensearch-config-v) |
| 資料平台 | `firehose-stream` | Firehose delivery stream：Kinesis 或 Direct PUT 來源，送到 S3（GZIP、時間 prefix）或 VPC 內的 OpenSearch（失敗文件備份到 S3），固定 KMS 加密與 CloudWatch logging | [![firehose-stream](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=firehose-stream-v*&label=)](https://github.com/libterty/infra-platform/releases?q=firehose-stream-v) |
| 資料平台 | `athena-workgroup` | Athena workgroup：強制 workgroup 設定、結果 SSE_KMS 加密、每次查詢掃描量上限，可附 named query | [![athena-workgroup](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=athena-workgroup-v*&label=)](https://github.com/libterty/infra-platform/releases?q=athena-workgroup-v) |
| 資料平台 | `redshift-cluster` | provisioned Redshift（RA3）：VPC 內、不公開、KMS 加密、密碼由 Redshift 代管、parameter group 固定 `require_ssl`、稽核 log 寫 CloudWatch Logs、預設做 final snapshot | [![redshift-cluster](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=redshift-cluster-v*&label=)](https://github.com/libterty/infra-platform/releases?q=redshift-cluster-v) |
| 資料平台 | `redshift-serverless` | Redshift Serverless（namespace 加 workgroup）：VPC 內、不公開、KMS 加密、密碼由 Redshift 代管、固定 `require_ssl`、稽核 log 寫 CloudWatch Logs，可設每月 RPU-小時用量上限 | [![redshift-serverless](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=redshift-serverless-v*&label=)](https://github.com/libterty/infra-platform/releases?q=redshift-serverless-v) |
| 資料平台 | `quicksight-data` | QuickSight 資料層：Athena 與 Redshift（secret 驗證）data source、VPC connection、dataset 與 user／group 權限；不管帳號訂閱 | [![quicksight-data](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=quicksight-data-v*&label=)](https://github.com/libterty/infra-platform/releases?q=quicksight-data-v) |
| 運算             | `ecs-cluster`               | Fargate cluster                                                                    | [![ecs-cluster](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=ecs-cluster-v*&label=)](https://github.com/libterty/infra-platform/releases?q=ecs-cluster-v) |
| 運算             | `ecs-service`               | Fargate service、autoscaling（含排程與 step policy）、Service Connect、可選 sidecar                        | [![ecs-service](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=ecs-service-v*&label=)](https://github.com/libterty/infra-platform/releases?q=ecs-service-v) |
| 運算             | `ecs-service-alarms`        | 服務告警                                                                           | [![ecs-service-alarms](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=ecs-service-alarms-v*&label=)](https://github.com/libterty/infra-platform/releases?q=ecs-service-alarms-v) |
| 運算 | `lambda-function` | container image 的 Lambda、log group、呼叫權限 | [![lambda-function](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=lambda-function-v*&label=)](https://github.com/libterty/infra-platform/releases?q=lambda-function-v) |
| 運算 | `ec2-bastion` | 只走 SSM 的 bastion：IMDSv2、沒有 public IP、加密 | [![ec2-bastion](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=ec2-bastion-v*&label=)](https://github.com/libterty/infra-platform/releases?q=ec2-bastion-v) |
| 運算 | `ec2-instance` | 單台 EC2：IMDSv2、沒有 public IP、加密碟，可選自動 recover 告警 | [![ec2-instance](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=ec2-instance-v*&label=)](https://github.com/libterty/infra-platform/releases?q=ec2-instance-v) |
| 運算 | `ec2-asg` | launch template 加 Auto Scaling group：可混 spot、ELB 健康檢查、instance refresh | [![ec2-asg](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=ec2-asg-v*&label=)](https://github.com/libterty/infra-platform/releases?q=ec2-asg-v) |
| 觀測性           | `log-group`                 | CloudWatch log group：保留天數、KMS、可選 subscription filter                      | [![log-group](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=log-group-v*&label=)](https://github.com/libterty/infra-platform/releases?q=log-group-v) |
| 觀測性           | `log-delivery`              | CloudWatch vended log（ALB、NLB、S3、CloudFront、EKS Auto Mode、AgentCore 等）的 source、destination、delivery | [![log-delivery](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=log-delivery-v*&label=)](https://github.com/libterty/infra-platform/releases?q=log-delivery-v) |
| 觀測性           | `log-metric-alarm`          | 從 log 產生指標，可選接告警                                                            | [![log-metric-alarm](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=log-metric-alarm-v*&label=)](https://github.com/libterty/infra-platform/releases?q=log-metric-alarm-v) |
| 觀測性 | `metric-alarm` | 任意 CloudWatch 指標或 metric math 的告警 | [![metric-alarm](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=metric-alarm-v*&label=)](https://github.com/libterty/infra-platform/releases?q=metric-alarm-v) |
| 觀測性           | `xray`                      | X-Ray sampling rule 與 group                                                       | [![xray](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=xray-v*&label=)](https://github.com/libterty/infra-platform/releases?q=xray-v) |
| 觀測性 | `xray-transaction-search` | 帳號層開啟 X-Ray Transaction Search：span 進 `aws/spans`、indexing 比例；每個帳號加 region 只呼叫一次 | [![xray-transaction-search](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=xray-transaction-search-v*&label=)](https://github.com/libterty/infra-platform/releases?q=xray-transaction-search-v) |
| 共用基礎         | `kms-key`                   | 對稱式 KMS key、key policy、alias                                                  | [![kms-key](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=kms-key-v*&label=)](https://github.com/libterty/infra-platform/releases?q=kms-key-v) |
| 共用基礎         | `ecr-repository`            | ECR repository 與 lifecycle policy                                                 | [![ecr-repository](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=ecr-repository-v*&label=)](https://github.com/libterty/infra-platform/releases?q=ecr-repository-v) |
| 共用基礎         | `s3-bucket`                 | S3 bucket：封鎖公開存取、加密、生命週期、只允許 TLS，可選 versioning、分層、Lambda 與 EventBridge 通知                       | [![s3-bucket](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=s3-bucket-v*&label=)](https://github.com/libterty/infra-platform/releases?q=s3-bucket-v) |
| 共用基礎         | `sns-alarm-topic`           | 告警 SNS topic                                                                     | [![sns-alarm-topic](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=sns-alarm-topic-v*&label=)](https://github.com/libterty/infra-platform/releases?q=sns-alarm-topic-v) |
| 共用基礎         | `security-group`            | 互相引用的 security group 與規則                                                   | [![security-group](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=security-group-v*&label=)](https://github.com/libterty/infra-platform/releases?q=security-group-v) |
| IAM              | `iam-role`                  | IAM role：trust policy 加 inline policy，可選 instance profile                                            | [![iam-role](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=iam-role-v*&label=)](https://github.com/libterty/infra-platform/releases?q=iam-role-v) |
| IAM              | `iam-role-policy`           | 對已存在的 role 附加 inline policy                                                 | [![iam-role-policy](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=iam-role-policy-v*&label=)](https://github.com/libterty/infra-platform/releases?q=iam-role-policy-v) |
| IAM | `iam-oidc-provider` | EKS 的 IAM OIDC provider，只給 Fargate 的 IRSA 用 | [![iam-oidc-provider](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=iam-oidc-provider-v*&label=)](https://github.com/libterty/infra-platform/releases?q=iam-oidc-provider-v) |
| 跨 stack 傳值    | `ssm-publish`               | 跨 stack 傳值的唯一寫入入口                                                        | [![ssm-publish](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=ssm-publish-v*&label=)](https://github.com/libterty/infra-platform/releases?q=ssm-publish-v) |
| 跨 stack 傳值    | `ssm-read`                  | 跨 stack 傳值的唯一讀取入口                                                        | [![ssm-read](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=ssm-read-v*&label=)](https://github.com/libterty/infra-platform/releases?q=ssm-read-v) |
| EKS | `eks-cluster` | EKS 叢集：managed node group、Karpenter、Fargate、Auto Mode，access entry、Pod Identity | [![eks-cluster](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=eks-cluster-v*&label=)](https://github.com/libterty/infra-platform/releases?q=eks-cluster-v) |
| EKS | `eks-addons` | 用 Helm 裝 LB Controller、Karpenter、Argo Rollouts 與預設 NodePool、app namespace | [![eks-addons](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=eks-addons-v*&label=)](https://github.com/libterty/infra-platform/releases?q=eks-addons-v) |
| EKS | `eks-iam-policies` | 不建資源，輸出 LB Controller、Karpenter、Argo Rollouts 的官方 IAM policy | [![eks-iam-policies](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=eks-iam-policies-v*&label=)](https://github.com/libterty/infra-platform/releases?q=eks-iam-policies-v) |
| EKS | `eks-workload-alarms` | EKS 工作負載告警：Ready 副本、CrashLoop、重啟、Pending、OOM，可選 ALB target 告警 | [![eks-workload-alarms](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=eks-workload-alarms-v*&label=)](https://github.com/libterty/infra-platform/releases?q=eks-workload-alarms-v) |
| LLM 與 AgentCore | `bedrock-guardrail`         | Bedrock guardrail，tier 預設 `STANDARD`                                          | [![bedrock-guardrail](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=bedrock-guardrail-v*&label=)](https://github.com/libterty/infra-platform/releases?q=bedrock-guardrail-v) |
| LLM 與 AgentCore | `bedrock-inference-profile` | application inference profile，給成本歸屬                                          | [![bedrock-inference-profile](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=bedrock-inference-profile-v*&label=)](https://github.com/libterty/infra-platform/releases?q=bedrock-inference-profile-v) |
| LLM 與 AgentCore | `agentcore-runtime`         | AgentCore Runtime                                                                  | [![agentcore-runtime](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=agentcore-runtime-v*&label=)](https://github.com/libterty/infra-platform/releases?q=agentcore-runtime-v) |
| LLM 與 AgentCore | `agentcore-memory`          | AgentCore Memory 與內建 strategy                                                   | [![agentcore-memory](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=agentcore-memory-v*&label=)](https://github.com/libterty/infra-platform/releases?q=agentcore-memory-v) |
| LLM 與 AgentCore | `agentcore-gateway`         | MCP Gateway，target 只收 Lambda 與 MCP server                                      | [![agentcore-gateway](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=agentcore-gateway-v*&label=)](https://github.com/libterty/infra-platform/releases?q=agentcore-gateway-v) |
| LLM 與 AgentCore | `bedrock-knowledge-base`    | Bedrock Knowledge Base（向量儲存只收 Aurora PostgreSQL pgvector）與 S3 data source | [![bedrock-knowledge-base](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=bedrock-knowledge-base-v*&label=)](https://github.com/libterty/infra-platform/releases?q=bedrock-knowledge-base-v) |

消費端寫法：

```hcl
module "api" {
  source  = "app.terraform.io/<org>/ecs-service/aws"
  version = "~> 0.1.0"
}
```

`<org>` 換成 HCP Terraform 的 organization。本 repo 的 module 發布在 `app.terraform.io/libterty`，這是 private registry，只有該 organization 的成員抓得到。不是成員或沒有 HCP token，就改用 `git::...?ref=<tag>` 的備案寫法。

表格的「最新版」是各 module 在 GitHub 上最新的 tag，去掉前綴就是 registry 上的版本號。

HCP 認證、升版、範本複製出去要改哪裡、git 備案怎麼寫，見 [`consuming-modules.md`](./docs/guides/consuming-modules.md)；module 怎麼登記到 HCP，見 [`hcp-registry-setup.md`](./docs/guides/hcp-registry-setup.md)。

## 範本

這裡有三份專案 infra 範本，都是完整的 Terraform stack 目錄，複製到專案 repo 就能用。三份的規則相同：stack 只呼叫 module，跨 stack 只透過 SSM 傳值。

| 範本 | 差異 |
| --- | --- |
| [`templates/project-infra/`](./templates/project-infra/infra/README.md) | 9 個 stack，環境是 `dev`、`prod`。IAM 拆成 `iam-base`、`iam-app` 兩個 stack，資料庫獨立成 `data`。`agent`（AgentCore 與 Bedrock）預設關閉。支援客戶自管資源模式 |
| [`templates/example2/`](./templates/example2/infra/README.md) | 11 個 stack，環境是 `dev`、`sit`。資料庫、IAM、ALB、AgentCore、ECS、bastion 與告警各自一個 stack。另有 `bridge` stack，把前段 stack 的值轉寫到後段讀取的共用前綴底下，這個前綴也可以改由外部發布。附 `stacks.sh` 與 SSM 合約檢查腳本 |
| [`templates/example3/`](./templates/example3/infra/README.md) | example2 的 EKS 版，13 個 stack。api 與 worker 跑在 EKS Auto Mode，由 CI 用 Helm 部署：Terraform 建叢集與平台元件，再把部署需要的值發布到 SSM；附範例 chart、SSM 轉 values 的腳本，以及預設關閉的 canary 與斷路器 |

## 不同團隊怎麼用

| 團隊          | 在這個 repo 做什麼                                                                       |
| ------------- | ---------------------------------------------------------------------------------------- |
| platform team | 擁有 `modules/`、`.github/`、`scripts/`、`docs/adr/`；維護 module 介面、CI、發版 |
| core app team | 目前沒有。AP 層的共用元件之後比照本 repo 的發版模式另開 repo                                   |
| 專案 app team | 複製 `templates/project-infra/`、`templates/example2/` 或 `templates/example3/` 到自己的 repo，釘版本引用 module |
| 專案 FDE team | 用 `scripts/vendor-modules.sh` 把指定 tag 的 module 交付給客戶                         |

團隊邊界寫在 [`.github/CODEOWNERS`](./.github/CODEOWNERS)，team slug 目前是佔位符。

## 開發

只需要 terraform（1.15.8）、tflint（0.64.0）、terraform-docs（0.24.x）、bash 與 jq，不需要任何 AWS 憑證。範本的 stack 從 `app.terraform.io/libterty` 抓 module，所以要先用該 organization 成員的帳號 `terraform login`：

```bash
scripts/validate.sh                      # 全部
scripts/validate.sh modules/ssm-publish  # 只跑指定目錄
scripts/validate.sh --changed-since origin/main  # 只跑這次改動影響得到的目錄
```

這支腳本依序做：`terraform fmt -check`、靜態規則 S1 到 S11（S11 用 terraform-docs 檢查 module README 的輸入／輸出表跟程式碼一致）、`terraform init -backend=false`、`validate`、`test`（`required_providers` 裡的每個 provider 都要有 `mock_provider`）、`tflint`。tflint 用內建的 terraform ruleset 加上 aws ruleset（`.tflint.hcl` 釘版本，不開 `deep_check`，不需要 AWS 憑證）；aws ruleset 是 plugin，第一次跑時 `tflint --init` 會從 GitHub 下載到 `.cache/tflint-plugins`，之後不連網。範本的 stack 另外用 `--call-module-type=all` 逐一帶入 `envs/` 底下的每份 tfvars 再跑一次 tflint，tfvars 裡的規格值（例如 ElastiCache 的 node type）也會被檢查；aws ruleset 沒有對應規則的 resource（例如 Aurora 的 `aws_rds_cluster_instance`）檢查不到。它一開頭就清掉所有 `AWS_*`、`KUBE*`、`HELM*` 環境變數，並把 AWS 設定檔與 `KUBECONFIG` 指到 `/dev/null`，所以漏寫 mock 的測試會失敗，不會拿到本機的 session 或叢集。module 裡如果有本地 Helm chart（`charts/`）或 Lambda 程式碼的測試（`lambda/test_*.py`），裝了 `helm`、`python3` 時也會一起檢查。CI（`.github/workflows/ci.yml`）跑同一支腳本：PR 用 `--changed-since`，push 到 main、每週排程與手動觸發跑全部。

`--changed-since <rev>` 的 fmt 與靜態規則仍然掃全部，`init` 到 `tflint` 只跑受影響的目錄：改到的目錄、用本地路徑（`./`、`../`）引用它的目錄（例如 module 的 examples），以及範本 stack 之外的檔案所屬範本的全部 stack。範本從 registry 抓 module，所以只改 module 不會重跑範本。`docs/`、`*.md` 不算改動；`scripts/`、`.tflint.hcl`、`.github/` 這類其他檔案一改就跑全部。

這個 repo 禁止跑 `terraform plan`、`apply`、帶 backend 的 `init`，以及任何 `aws` 指令。

commit 用 Conventional Commits：`<type>(<scope>): <subject>`，scope 寫 module 名稱或 `repo`。一個 commit 只動一個 module 目錄，因為 release-please 靠路徑判斷變更要記進哪個 module 的 CHANGELOG。

參與方式見 [`CONTRIBUTING.md`](./CONTRIBUTING.md)，安全問題照 [`SECURITY.md`](./SECURITY.md) 私下回報，授權是 Apache-2.0（[`LICENSE`](./LICENSE)）。

## 文件地圖

| 想知道什麼                                                                                           | 去哪裡                                                                                                                                                                                                                                                        |
| ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 為什麼這樣設計、module 介面、stack 清單、SSM 合約                                                    | [`docs/design/v1/design-docs.md`](./docs/design/v1/design-docs.md)                                                                                                                                                                                           |
| 實作步驟與每個 Phase 的驗收                                                                          | [`docs/design/v1/implement-process.md`](./docs/design/v1/implement-process.md)                                                                                                                                                                               |
| 第二份範本 example2 的設計、實作步驟；把既有專案改寫成範本的流程 | [`docs/design/v2/`](./docs/design/v2/design-docs.md)：[實作步驟](./docs/design/v2/implement-process.md)、[整合流程](./docs/design/v2/integration-playbook.md) |
| EC2、EKS、ALB／NLB 權重分流與斷路器的設計與實作步驟 | [`docs/design/v3/`](./docs/design/v3/design-docs.md)：[實作步驟](./docs/design/v3/implement-process.md) |
| 第三份範本 example3（example2 的 EKS 版）的設計與實作步驟 | [`docs/design/v4/`](./docs/design/v4/design-docs.md)：[實作步驟](./docs/design/v4/implement-process.md) |
| 架構決策                                                                                             | [`docs/adr/`](./docs/adr/)：[0001 registry 機制](./docs/adr/0001-git-tag-monorepo-as-private-registry.md)、[0002 state 拆分](./docs/adr/0002-split-state-by-owner-and-change-rate.md)、[0003 跨 stack 傳值](./docs/adr/0003-cross-stack-values-via-ssm-only.md)、[0004 HCP registry](./docs/adr/0004-hcp-terraform-private-registry.md) |
| 怎麼引用 module、HCP 認證、升版、git 備案                                                                | [`docs/guides/consuming-modules.md`](./docs/guides/consuming-modules.md)                                                                                                                                                                                     |
| 怎麼把 module 登記到 HCP Terraform private registry | [`docs/guides/hcp-registry-setup.md`](./docs/guides/hcp-registry-setup.md) |
| 專案怎麼照範本開 `infra/`：stack 拆分、apply 順序、單一決定點、環境切換、客戶自管模式              | [`docs/guides/project-infra-standard.md`](./docs/guides/project-infra-standard.md)；範本本身在 [`templates/project-infra/infra/`](./templates/project-infra/infra/README.md)、[`templates/example2/infra/`](./templates/example2/infra/README.md) 與 [`templates/example3/infra/`](./templates/example3/infra/README.md)                                                                                |
| 怎麼改 module、semver、release-please、第一次手動打 tag                                              | [`docs/guides/releasing-modules.md`](./docs/guides/releasing-modules.md)                                                                                                                                                                                     |
| ADOT sidecar、X-Ray 權限與抽樣、log 告警                                                             | [`docs/guides/observability.md`](./docs/guides/observability.md)                                                                                                                                                                                             |
| example3 第一次在真實帳號驗證：每一項的前提、指令、預期結果 | [`docs/guides/cloud-verification-example3.md`](./docs/guides/cloud-verification-example3.md) |
| LLM 與 AgentCore：Runtime、guardrail、Memory、Gateway、Knowledge Base（Aurora pgvector）怎麼接進範本 | [`docs/guides/llm-agentcore.md`](./docs/guides/llm-agentcore.md)                                                                                                                                                                                             |
| FDE 交付：vendoring、provider 鏡像、客戶自管的 SSM 合約                                              | [`docs/guides/delivering-to-customer.md`](./docs/guides/delivering-to-customer.md)                                                                                                                                                                           |
| 四個團隊的責任與交接點                                                                               | [`docs/guides/team-roles.md`](./docs/guides/team-roles.md)                                                                                                                                                                                                   |
