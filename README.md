# infra-platform

[![CI](https://github.com/libterty/infra-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/libterty/infra-platform/actions/workflows/ci.yml) [![Registry](https://img.shields.io/badge/registry-app.terraform.io%2Flibterty-7B42BC?logo=terraform&logoColor=white)](https://app.terraform.io/app/libterty/registry/private/modules)

這是 Terraform private registry 的範例 repo。共用 module 都放在這個 monorepo，用 Git tag 標版本，透過 HCP Terraform private registry 發布。各專案用版本範圍引用同一份 module，不用每個專案各寫一套。

## module

共 32 個 module，tag 格式是 `<module>-v<MAJOR>.<MINOR>.<PATCH>`。

| 分類             | module                        | 用途                                                                               | 最新版 |
| ---------------- | ----------------------------- | ---------------------------------------------------------------------------------- | --- |
| 網路與入口       | `vpc`                       | VPC、分層 subnet、NAT、gateway endpoint、flow log                                  | [![vpc](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=vpc-v*&label=)](https://github.com/libterty/infra-platform/releases?q=vpc-v) |
| 網路與入口       | `vpc-interface-endpoints`   | interface endpoint（PrivateLink）與共用的 SG                                       | [![vpc-interface-endpoints](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=vpc-interface-endpoints-v*&label=)](https://github.com/libterty/infra-platform/releases?q=vpc-interface-endpoints-v) |
| 網路與入口       | `alb`                       | ALB、listener、target group 與 listener rule、ELB 5xx 告警                                                        | [![alb](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=alb-v*&label=)](https://github.com/libterty/infra-platform/releases?q=alb-v) |
| 網路與入口 | `waf-web-acl` | REGIONAL WAF web ACL：kill switch、rate limit、managed rule、body size、log 遮蔽 | [![waf-web-acl](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=waf-web-acl-v*&label=)](https://github.com/libterty/infra-platform/releases?q=waf-web-acl-v) |
| 網路與入口 | `vpc-peering` | VPC peering 請求端與路由 | [![vpc-peering](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=vpc-peering-v*&label=)](https://github.com/libterty/infra-platform/releases?q=vpc-peering-v) |
| 資料             | `rds`                       | RDS、Aurora、Aurora Serverless v2，可選 RDS Proxy                                  | [![rds](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=rds-v*&label=)](https://github.com/libterty/infra-platform/releases?q=rds-v) |
| 資料 | `elasticache-redis` | ElastiCache Redis（cluster mode）：固定加密與 multi-AZ、可選 shard autoscaling、告警 | [![elasticache-redis](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=elasticache-redis-v*&label=)](https://github.com/libterty/infra-platform/releases?q=elasticache-redis-v) |
| 運算             | `ecs-cluster`               | Fargate cluster                                                                    | [![ecs-cluster](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=ecs-cluster-v*&label=)](https://github.com/libterty/infra-platform/releases?q=ecs-cluster-v) |
| 運算             | `ecs-service`               | Fargate service、autoscaling（含排程與 step policy）、Service Connect、可選 sidecar                        | [![ecs-service](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=ecs-service-v*&label=)](https://github.com/libterty/infra-platform/releases?q=ecs-service-v) |
| 運算             | `ecs-service-alarms`        | 服務告警                                                                           | [![ecs-service-alarms](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=ecs-service-alarms-v*&label=)](https://github.com/libterty/infra-platform/releases?q=ecs-service-alarms-v) |
| 運算 | `lambda-function` | container image 的 Lambda、log group、呼叫權限 | [![lambda-function](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=lambda-function-v*&label=)](https://github.com/libterty/infra-platform/releases?q=lambda-function-v) |
| 運算 | `ec2-bastion` | 只走 SSM 的 bastion：IMDSv2、沒有 public IP、加密 | [![ec2-bastion](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=ec2-bastion-v*&label=)](https://github.com/libterty/infra-platform/releases?q=ec2-bastion-v) |
| 觀測性           | `log-group`                 | CloudWatch log group：保留天數、KMS、可選 subscription filter                      | [![log-group](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=log-group-v*&label=)](https://github.com/libterty/infra-platform/releases?q=log-group-v) |
| 觀測性           | `log-metric-alarm`          | 從 log 產生指標，可選接告警                                                            | [![log-metric-alarm](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=log-metric-alarm-v*&label=)](https://github.com/libterty/infra-platform/releases?q=log-metric-alarm-v) |
| 觀測性 | `metric-alarm` | 任意 CloudWatch 指標或 metric math 的告警 | [![metric-alarm](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=metric-alarm-v*&label=)](https://github.com/libterty/infra-platform/releases?q=metric-alarm-v) |
| 觀測性           | `xray`                      | X-Ray sampling rule 與 group                                                       | [![xray](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=xray-v*&label=)](https://github.com/libterty/infra-platform/releases?q=xray-v) |
| 共用基礎         | `kms-key`                   | 對稱式 KMS key、key policy、alias                                                  | [![kms-key](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=kms-key-v*&label=)](https://github.com/libterty/infra-platform/releases?q=kms-key-v) |
| 共用基礎         | `ecr-repository`            | ECR repository 與 lifecycle policy                                                 | [![ecr-repository](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=ecr-repository-v*&label=)](https://github.com/libterty/infra-platform/releases?q=ecr-repository-v) |
| 共用基礎         | `s3-bucket`                 | S3 bucket：封鎖公開存取、加密、生命週期、只允許 TLS，可選 versioning 與 Lambda 通知                       | [![s3-bucket](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=s3-bucket-v*&label=)](https://github.com/libterty/infra-platform/releases?q=s3-bucket-v) |
| 共用基礎         | `sns-alarm-topic`           | 告警 SNS topic                                                                     | [![sns-alarm-topic](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=sns-alarm-topic-v*&label=)](https://github.com/libterty/infra-platform/releases?q=sns-alarm-topic-v) |
| 共用基礎         | `security-group`            | 互相引用的 security group 與規則                                                   | [![security-group](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=security-group-v*&label=)](https://github.com/libterty/infra-platform/releases?q=security-group-v) |
| IAM              | `iam-role`                  | IAM role：trust policy 加 inline policy，可選 instance profile                                            | [![iam-role](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=iam-role-v*&label=)](https://github.com/libterty/infra-platform/releases?q=iam-role-v) |
| IAM              | `iam-role-policy`           | 對已存在的 role 附加 inline policy                                                 | [![iam-role-policy](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=iam-role-policy-v*&label=)](https://github.com/libterty/infra-platform/releases?q=iam-role-policy-v) |
| 跨 stack 傳值    | `ssm-publish`               | 跨 stack 傳值的唯一寫入入口                                                        | [![ssm-publish](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=ssm-publish-v*&label=)](https://github.com/libterty/infra-platform/releases?q=ssm-publish-v) |
| 跨 stack 傳值    | `ssm-read`                  | 跨 stack 傳值的唯一讀取入口                                                        | [![ssm-read](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=ssm-read-v*&label=)](https://github.com/libterty/infra-platform/releases?q=ssm-read-v) |
| LLM 與 AgentCore | `bedrock-guardrail`         | Bedrock guardrail，tier 預設 `STANDARD`                                          | [![bedrock-guardrail](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=bedrock-guardrail-v*&label=)](https://github.com/libterty/infra-platform/releases?q=bedrock-guardrail-v) |
| LLM 與 AgentCore | `bedrock-inference-profile` | application inference profile，給成本歸屬                                          | [![bedrock-inference-profile](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=bedrock-inference-profile-v*&label=)](https://github.com/libterty/infra-platform/releases?q=bedrock-inference-profile-v) |
| LLM 與 AgentCore | `agentcore-runtime`         | AgentCore Runtime                                                                  | [![agentcore-runtime](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=agentcore-runtime-v*&label=)](https://github.com/libterty/infra-platform/releases?q=agentcore-runtime-v) |
| LLM 與 AgentCore | `agentcore-memory`          | AgentCore Memory 與內建 strategy                                                   | [![agentcore-memory](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=agentcore-memory-v*&label=)](https://github.com/libterty/infra-platform/releases?q=agentcore-memory-v) |
| LLM 與 AgentCore | `agentcore-gateway`         | MCP Gateway，target 只收 Lambda 與 MCP server                                      | [![agentcore-gateway](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=agentcore-gateway-v*&label=)](https://github.com/libterty/infra-platform/releases?q=agentcore-gateway-v) |
| LLM 與 AgentCore | `log-delivery`              | CloudWatch vended log 的 source、destination、delivery                             | [![log-delivery](https://img.shields.io/github/v/tag/libterty/infra-platform?filter=log-delivery-v*&label=)](https://github.com/libterty/infra-platform/releases?q=log-delivery-v) |
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

這裡有兩份專案 infra 範本，都是完整的 Terraform stack 目錄，複製到專案 repo 就能用。兩份的規則相同：stack 只呼叫 module，跨 stack 只透過 SSM 傳值。

| 範本 | 差異 |
| --- | --- |
| [`templates/project-infra/`](./templates/project-infra/infra/README.md) | 9 個 stack，環境是 `dev`、`prod`。IAM 拆成 `iam-base`、`iam-app` 兩個 stack，資料庫獨立成 `data`。`agent`（AgentCore 與 Bedrock）預設關閉。支援客戶自管資源模式 |
| [`templates/example2/`](./templates/example2/infra/README.md) | 11 個 stack，環境是 `dev`、`sit`。資料庫、IAM、ALB、AgentCore、ECS、bastion 與告警各自一個 stack。另有 `bridge` stack，把前段 stack 的值轉寫到後段讀取的共用前綴底下，這個前綴也可以改由外部發布。附 `stacks.sh` 與 SSM 合約檢查腳本 |

## 不同團隊怎麼用

| 團隊          | 在這個 repo 做什麼                                                                       |
| ------------- | ---------------------------------------------------------------------------------------- |
| platform team | 擁有 `modules/`、`.github/`、`scripts/`、`docs/adr/`；維護 module 介面、CI、發版 |
| core app team | 目前沒有。AP 層的共用元件之後比照本 repo 的發版模式另開 repo                                   |
| 專案 app team | 複製 `templates/project-infra/` 或 `templates/example2/` 到自己的 repo，釘版本引用 module |
| 專案 FDE team | 用 `scripts/vendor-modules.sh` 把指定 tag 的 module 交付給客戶                         |

團隊邊界寫在 [`.github/CODEOWNERS`](./.github/CODEOWNERS)，team slug 目前是佔位符。

## 開發

只需要 terraform（1.15.8）、tflint（0.64.0）、bash 與 jq，不需要任何 AWS 憑證。範本的 stack 從 `app.terraform.io/libterty` 抓 module，所以要先用該 organization 成員的帳號 `terraform login`：

```bash
scripts/validate.sh                      # 全部
scripts/validate.sh modules/ssm-publish  # 只跑指定目錄
```

這支腳本依序做：`terraform fmt -check`、靜態規則 S1 到 S10、`terraform init -backend=false`、`validate`、`test`（測試一律用 `mock_provider "aws"`）、`tflint`。它一開頭就清掉所有 `AWS_*` 環境變數，並把設定檔指到 `/dev/null`，所以漏寫 mock 的測試會失敗，不會拿到本機的 session。CI（`.github/workflows/ci.yml`）跑同一支腳本。

這個 repo 禁止跑 `terraform plan`、`apply`、帶 backend 的 `init`，以及任何 `aws` 指令。

commit 用 Conventional Commits：`<type>(<scope>): <subject>`，scope 寫 module 名稱或 `repo`。一個 commit 只動一個 module 目錄，因為 release-please 靠路徑判斷變更要記進哪個 module 的 CHANGELOG。

## 文件地圖

| 想知道什麼                                                                                           | 去哪裡                                                                                                                                                                                                                                                        |
| ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 為什麼這樣設計、module 介面、stack 清單、SSM 合約                                                    | [`docs/design/v1/design-docs.md`](./docs/design/v1/design-docs.md)                                                                                                                                                                                           |
| 實作步驟與每個 Phase 的驗收                                                                          | [`docs/design/v1/implement-process.md`](./docs/design/v1/implement-process.md)                                                                                                                                                                               |
| 第二份範本 example2 的設計、實作步驟；把既有專案改寫成範本的流程 | [`docs/design/v2/`](./docs/design/v2/design-docs.md)：[實作步驟](./docs/design/v2/implement-process.md)、[整合流程](./docs/design/v2/integration-playbook.md) |
| 架構決策                                                                                             | [`docs/adr/`](./docs/adr/)：[0001 registry 機制](./docs/adr/0001-git-tag-monorepo-as-private-registry.md)、[0002 state 拆分](./docs/adr/0002-split-state-by-owner-and-change-rate.md)、[0003 跨 stack 傳值](./docs/adr/0003-cross-stack-values-via-ssm-only.md)、[0004 HCP registry](./docs/adr/0004-hcp-terraform-private-registry.md) |
| 怎麼引用 module、HCP 認證、升版、git 備案                                                                | [`docs/guides/consuming-modules.md`](./docs/guides/consuming-modules.md)                                                                                                                                                                                     |
| 怎麼把 module 登記到 HCP Terraform private registry | [`docs/guides/hcp-registry-setup.md`](./docs/guides/hcp-registry-setup.md) |
| 專案怎麼照範本開 `infra/`：stack 拆分、apply 順序、單一決定點、環境切換、客戶自管模式              | [`docs/guides/project-infra-standard.md`](./docs/guides/project-infra-standard.md)；範本本身在 [`templates/project-infra/infra/`](./templates/project-infra/infra/README.md) 與 [`templates/example2/infra/`](./templates/example2/infra/README.md)                                                                                |
| 怎麼改 module、semver、release-please、第一次手動打 tag                                              | [`docs/guides/releasing-modules.md`](./docs/guides/releasing-modules.md)                                                                                                                                                                                     |
| ADOT sidecar、X-Ray 權限與抽樣、log 告警                                                             | [`docs/guides/observability.md`](./docs/guides/observability.md)                                                                                                                                                                                             |
| LLM 與 AgentCore：Runtime、guardrail、Memory、Gateway、Knowledge Base（Aurora pgvector）怎麼接進範本 | [`docs/guides/llm-agentcore.md`](./docs/guides/llm-agentcore.md)                                                                                                                                                                                             |
| FDE 交付：vendoring、provider 鏡像、客戶自管的 SSM 合約                                              | [`docs/guides/delivering-to-customer.md`](./docs/guides/delivering-to-customer.md)                                                                                                                                                                           |
| 四個團隊的責任與交接點                                                                               | [`docs/guides/team-roles.md`](./docs/guides/team-roles.md)                                                                                                                                                                                                   |
