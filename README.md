# infra-platform

Terraform private registry 的範例 repo：用 Git tag 版本化的 monorepo 發布共用 module，各專案用 `?ref=<module>-v<semver>` 釘版本引用，不再每個專案各寫一套。

第一版做出最小三層架構：ALB 在 public subnet，ECS 服務與資料庫在 private subnet。內容是 15 個 module、1 份 8 個 stack 的專案 infra 範本，以及使用與發版文件。全部只做離線驗證，不做 `plan`／`apply`，也不碰任何 AWS 帳號。

目前進度：8 個 module 已完成；另外 7 個 module、專案範本與使用文件依 `docs/design/v1/implement-process.md` 的 Phase 7–10 進行。

## module

起始版本都是 `v0.1.0`，tag 格式是 `<module>-v<MAJOR>.<MINOR>.<PATCH>`（見 [ADR-0001](./docs/adr/0001-git-tag-monorepo-as-private-registry.md)）。

| 分類 | module | 用途 |
|---|---|---|
| 網路與入口 | `vpc` | VPC、分層 subnet、NAT、endpoint、flow log |
| 網路與入口 | `alb` | ALB、listener、ELB 5xx 告警 |
| 資料 | `rds` | 一般 RDS、Aurora、Aurora Serverless v2，可選 RDS Proxy |
| 運算 | `ecs-cluster` | Fargate cluster |
| 運算 | `ecs-service` | Fargate service、autoscaling、Service Connect |
| 運算 | `ecs-service-alarms` | 服務告警 |
| 共用基礎 | `kms-key` | 對稱式 KMS key、key policy、alias |
| 共用基礎 | `ecr-repository` | ECR repository 與 lifecycle policy |
| 共用基礎 | `s3-bucket` | log 用的 S3 bucket：封鎖公開存取、加密、生命週期、只允許 TLS |
| 共用基礎 | `sns-alarm-topic` | 告警 SNS topic |
| 共用基礎 | `security-group` | 一組互相引用的 security group 與規則 |
| IAM | `iam-role` | IAM role：trust policy 加 inline policy |
| IAM | `iam-role-policy` | 對已存在的 role 附加 inline policy |
| 跨 stack 傳值 | `ssm-publish` | 跨 stack 傳值的唯一寫入入口 |
| 跨 stack 傳值 | `ssm-read` | 跨 stack 傳值的唯一讀取入口 |

消費端寫法：

```hcl
module "api" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ecs-service?ref=ecs-service-v0.1.0"
}
```

`<org>`、`<repo>` 尚未決定，先用佔位符。

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

這支腳本依序做：`terraform fmt -check`、靜態規則 S1 到 S8、`terraform init -backend=false`、`validate`、`test`（測試一律用 `mock_provider "aws"`）、`tflint`。它一開頭就清掉所有 `AWS_*` 環境變數，並把設定檔指到 `/dev/null`，所以漏寫 mock 的測試會失敗，不會拿到本機的 session。CI（`.github/workflows/ci.yml`）跑同一支腳本。

本專案禁止在這個 repo 跑 `terraform plan`、`apply`、帶 backend 的 `init`，以及任何 `aws` 指令。

commit 用 Conventional Commits：`<type>(<scope>): <subject>`，scope 是 module 名稱或 `repo`。一個 commit 只動一個 module 目錄，release-please 才能依路徑歸屬各 module 的 CHANGELOG。

## 文件地圖

| 想知道什麼 | 去哪裡 |
|---|---|
| 為什麼這樣設計、module 介面、stack 清單、SSM 合約 | [`docs/design/v1/design-docs.md`](./docs/design/v1/design-docs.md) |
| 實作步驟與每個 Phase 的驗收 | [`docs/design/v1/implement-process.md`](./docs/design/v1/implement-process.md) |
| 架構決策 | [`docs/adr/`](./docs/adr/)：[0001 registry 機制](./docs/adr/0001-git-tag-monorepo-as-private-registry.md)、[0002 state 拆分](./docs/adr/0002-split-state-by-owner-and-change-rate.md)、[0003 跨 stack 傳值](./docs/adr/0003-cross-stack-values-via-ssm-only.md) |
| 使用指南（`docs/guides/`） | Phase 7 補：`consuming-modules.md`、`project-infra-standard.md`、`releasing-modules.md`、`delivering-to-customer.md`、`team-roles.md` |
