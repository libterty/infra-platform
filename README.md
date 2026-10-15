# infra-platform

Terraform private registry 的範例 repo：用 Git tag 版本化的 monorepo 發布共用 module，各專案用 `?ref=<module>-v<semver>` 釘版本引用，不再每個專案各寫一套。

第一版做出最小三層架構：ALB 在 public subnet，ECS 服務與資料庫在 private subnet。內容是 19 個 module、1 份 8 個 stack 的專案 infra 範本，以及使用與發版文件。全部只做離線驗證，不做 `plan`／`apply`，也不碰任何 AWS 帳號。

目前進度：19 個 module、8 個 stack 的專案範本、六份使用指南與 `scripts/vendor-modules.sh` 已完成，範本也接好了預設關閉的 X-Ray 追蹤；Phase 0–10 全部完成，驗收結果見下方文件地圖的實作步驟。19 個 `<module>-v0.1.0` tag 已打在 `28a8647`。本 repo 是範例，不部署到 AWS（2026-10-15 決定）。發版步驟見 [`releasing-modules.md`](./docs/guides/releasing-modules.md)。

## module

共 26 個：v1 的 19 個加增補的 7 個（LLM 與 AgentCore，設計文件決策 37）。起始版本都是 `v0.1.0`，tag 格式是 `<module>-v<MAJOR>.<MINOR>.<PATCH>`（見 [ADR-0001](./docs/adr/0001-git-tag-monorepo-as-private-registry.md)）。增補的 7 個還沒有 tag，跟 `rds-v0.2.0`、`s3-bucket-v0.2.0` 一起在增補驗收後手動打（[`releasing-modules.md`](./docs/guides/releasing-modules.md)）。

| 分類 | module | 用途 |
|---|---|---|
| 網路與入口 | `vpc` | VPC、分層 subnet、NAT、gateway endpoint、flow log |
| 網路與入口 | `vpc-interface-endpoints` | interface endpoint（PrivateLink）與共用的 SG |
| 網路與入口 | `alb` | ALB、listener、ELB 5xx 告警 |
| 資料 | `rds` | 一般 RDS、Aurora、Aurora Serverless v2，可選 RDS Proxy |
| 運算 | `ecs-cluster` | Fargate cluster |
| 運算 | `ecs-service` | Fargate service、autoscaling、Service Connect、可選 sidecar |
| 運算 | `ecs-service-alarms` | 服務告警 |
| 觀測性 | `log-group` | CloudWatch log group：保留天數、KMS、可選 subscription filter |
| 觀測性 | `log-metric-alarm` | 從 log 產生指標並接告警 |
| 觀測性 | `xray` | X-Ray sampling rule 與 group |
| 共用基礎 | `kms-key` | 對稱式 KMS key、key policy、alias |
| 共用基礎 | `ecr-repository` | ECR repository 與 lifecycle policy |
| 共用基礎 | `s3-bucket` | log 用的 S3 bucket：封鎖公開存取、加密、生命週期、只允許 TLS |
| 共用基礎 | `sns-alarm-topic` | 告警 SNS topic |
| 共用基礎 | `security-group` | 一組互相引用的 security group 與規則 |
| IAM | `iam-role` | IAM role：trust policy 加 inline policy |
| IAM | `iam-role-policy` | 對已存在的 role 附加 inline policy |
| 跨 stack 傳值 | `ssm-publish` | 跨 stack 傳值的唯一寫入入口 |
| 跨 stack 傳值 | `ssm-read` | 跨 stack 傳值的唯一讀取入口 |
| LLM 與 AgentCore | `bedrock-guardrail` | 一支 Bedrock guardrail，tier 預設 `STANDARD` |
| LLM 與 AgentCore | `bedrock-inference-profile` | application inference profile，給成本歸屬 |
| LLM 與 AgentCore | `agentcore-runtime` | 一個 AgentCore Runtime |
| LLM 與 AgentCore | `agentcore-memory` | 一個 AgentCore Memory 與內建 strategy |
| LLM 與 AgentCore | `agentcore-gateway` | MCP Gateway，target 只收 Lambda 與 MCP server |
| LLM 與 AgentCore | `log-delivery` | CloudWatch vended log 的 source、destination、delivery |
| LLM 與 AgentCore | `bedrock-knowledge-base` | Bedrock Knowledge Base（向量儲存只收 Aurora PostgreSQL pgvector）與 S3 data source |

消費端寫法：

```hcl
module "api" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ecs-service?ref=ecs-service-v0.1.0"
}
```

`<org>`、`<repo>` 尚未決定，先用佔位符。認證、升版與從範本複製出去的改法見 [`consuming-modules.md`](./docs/guides/consuming-modules.md)。

## 四個團隊怎麼用

| 團隊 | 在這個 repo 做什麼 |
|---|---|
| platform team | 擁有 `modules/`、`.github/`、`scripts/`、`docs/adr/`；維護 module 介面、CI、發版 |
| core app team | 暫無；AP 層共用元件之後比照本 repo 的發版模式另開 repo |
| 專案 app team | 複製 `templates/project-infra/` 到自己的 repo，釘版本引用 module |
| 專案 FDE team | 用 `scripts/vendor-modules.sh` 把指定 tag 的 module 交付給客戶 |

團隊邊界由 [`.github/CODEOWNERS`](./.github/CODEOWNERS) 表達，team slug 目前是佔位符。

## 開發

只需要 terraform（1.15.8）、tflint（0.64.0）與 bash，不需要任何 AWS 憑證：

```bash
scripts/validate.sh                      # 全部
scripts/validate.sh modules/ssm-publish  # 只跑指定目錄
```

這支腳本依序做：`terraform fmt -check`、靜態規則 S1 到 S9、`terraform init -backend=false`、`validate`、`test`（測試一律用 `mock_provider "aws"`）、`tflint`。它一開頭就清掉所有 `AWS_*` 環境變數，並把設定檔指到 `/dev/null`，所以漏寫 mock 的測試會失敗，不會拿到本機的 session。CI（`.github/workflows/ci.yml`）跑同一支腳本。

本專案禁止在這個 repo 跑 `terraform plan`、`apply`、帶 backend 的 `init`，以及任何 `aws` 指令。

commit 用 Conventional Commits：`<type>(<scope>): <subject>`，scope 是 module 名稱或 `repo`。一個 commit 只動一個 module 目錄，release-please 才能依路徑歸屬各 module 的 CHANGELOG。

## 文件地圖

| 想知道什麼 | 去哪裡 |
|---|---|
| 為什麼這樣設計、module 介面、stack 清單、SSM 合約 | [`docs/design/v1/design-docs.md`](./docs/design/v1/design-docs.md) |
| 實作步驟與每個 Phase 的驗收 | [`docs/design/v1/implement-process.md`](./docs/design/v1/implement-process.md) |
| 架構決策 | [`docs/adr/`](./docs/adr/)：[0001 registry 機制](./docs/adr/0001-git-tag-monorepo-as-private-registry.md)、[0002 state 拆分](./docs/adr/0002-split-state-by-owner-and-change-rate.md)、[0003 跨 stack 傳值](./docs/adr/0003-cross-stack-values-via-ssm-only.md) |
| 怎麼引用 module、私有 repo 認證、升版 | [`docs/guides/consuming-modules.md`](./docs/guides/consuming-modules.md) |
| 專案怎麼照範本開 `infra/`：stack 拆分、apply 順序、單一決定點、環境切換、客戶自管模式 | [`docs/guides/project-infra-standard.md`](./docs/guides/project-infra-standard.md)；範本本身在 [`templates/project-infra/infra/`](./templates/project-infra/infra/README.md) |
| 怎麼改 module、semver、release-please、第一次手動打 tag | [`docs/guides/releasing-modules.md`](./docs/guides/releasing-modules.md) |
| ADOT sidecar、X-Ray 權限與抽樣、log 告警 | [`docs/guides/observability.md`](./docs/guides/observability.md) |
| FDE 交付：vendoring、provider 鏡像、客戶自管的 SSM 合約 | [`docs/guides/delivering-to-customer.md`](./docs/guides/delivering-to-customer.md) |
| 四個團隊的責任與交接點 | [`docs/guides/team-roles.md`](./docs/guides/team-roles.md) |
