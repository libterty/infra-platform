---
status: "accepted"
date: 2026-10-14
decision-makers: platform team
outcome: "共用 module 放在同一個 repo 的 `modules/<name>/`，用 `<module>-v<MAJOR>.<MINOR>.<PATCH>` 的 git tag 各自發版，消費端用 `git::...//modules/<name>?ref=<tag>` 引用。不架 registry server；要版本範圍或 clone 變慢時升級到 HCP Terraform Free 或 boring-registry，module 程式碼不用改。"
notes: "Git source 不支援 `version = \"~> 1.2\"`，升版是消費端改 `ref` 的明確 PR。tag 可以被移動，要用 GitHub ruleset 保護 `*-v*`。每次 init 都 clone 整個 repo，repo 變大是升級訊號之一。0.x 期間 MINOR 可以有破壞性變更，第一版 8 個 module 起始都是 v0.1.0。"
---

# 用 Git tag 版本化的 monorepo 當 private registry

## Context and Problem Statement

各專案的 Terraform 目前是各寫一套：同一件事（VPC、ECS、告警、跨 stack 傳值）在不同專案有不同寫法，品質落差大，修一個 bug 要改很多個 repo。需要一個共用 module 的發布機制，讓專案用明確的版本引用，升版是看得見的動作。

問題是：**第一版用什麼機制發布共用 module？** 目前沒有 registry server、沒有 HCP Terraform 帳號，而且只有 8 個 module、少數幾個消費端。

## Decision Drivers

* 第一版要零基礎設施：不想先維運一個服務才能開始用。
* Terraform 原生支援，不改工具鏈。
* 每個 module 各自版本、各自 CHANGELOG，消費端可以只升一個 module。
* 之後換成真 registry 時，module 程式碼與目錄不用重寫。
* 客戶環境（FDE 交付）也要接得上，憑證不能依賴只有我們有的 registry token。

## Considered Options

* Git tag monorepo：一個 repo，`modules/<name>/`，per-module tag
* HCP Terraform Free 的 private registry
* 自架 boring-registry（S3 當後端）
* 一個 module 一個 repo

## Decision Outcome

Chosen option: 「Git tag monorepo」，因為它不需要任何額外基礎設施，Terraform 原生支援 Git source，而且目錄與 tag 照 registry 規範，之後升級不用動 module。

tag 格式是 `<module>-v<MAJOR>.<MINOR>.<PATCH>`，例如 `ecs-service-v1.0.0`。這是 release-please manifest 模式的預設格式，也對得上 HCP Terraform 的 Module Tag Prefix；不用帶斜線的 `ecs-service/v1.0.0`，因為 HCP 是否支援沒有查證，斜線放在 `?ref=` 也容易出錯。

消費端寫法：

```hcl
module "api" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ecs-service?ref=ecs-service-v1.0.0"
}
```

`<org>`、`<repo>` 尚未決定，文件一律用佔位符。

### Consequences

* Good: 零基礎設施，馬上可用；每個 module 各自 tag、各自 CHANGELOG。
* Good: 憑證全靠 git（`gh auth setup-git`、SSH、CI 的唯讀 deploy key），Terraform 本身沒有 registry token 這一層。
* Bad: 不支援版本範圍，不能自動吃 patch 版，升版一定是消費端改 `ref`。
* Bad: tag 可以被移動或刪除；要用 GitHub ruleset 保護 `*-v*`，要求更嚴格的專案改釘 commit SHA。
* Bad: 每次 `terraform init` 都 clone 整個 repo，隨 repo 變大而變慢。
* Neutral: 0.x 期間 MINOR 可以有破壞性變更；第一版 8 個 module 都從 v0.1.0 開始，真實 AWS 驗證完才升 v1.0.0。

### Confirmation

tag 由 release-please 以 `include-component-in-tag` 產生。第一批由人手動打：v1 的 19 個打 `v0.1.0`，LLM 增補動到的 10 個（7 個新 module 加 `rds`、`s3-bucket`、`iam-role`）打 `v0.1.1`，見 `docs/guides/releasing-modules.md`。`scripts/vendor-modules.sh` 會拒絕不符合 `^<module>-v[0-9]+\.[0-9]+\.[0-9]+$` 或前綴跟 module 對不上的 tag，module 清單從 `modules/` 目錄讀，不手寫。`scripts/validate.sh` 與 CI 不檢查 tag：它們驗的是程式碼，repo 裡的 tag 不經過它們。

## Pros and Cons of the Options

### Git tag monorepo

* Good: 零基礎設施、原生支援、目錄符合 registry 規範。
* Bad: 沒有版本範圍；tag 可被移動；clone 整個 repo。

### HCP Terraform Free 的 private registry

* Good: 有版本範圍（`~> 1.2`），不用自己維運。
* Bad: 要先有 HCP 帳號與 VCS 連結，第一版還沒有；Free 方案有 500 個 managed resource 上限，只用 registry 時是否計入沒有查證。
* Bad: 客戶環境不一定連得到 HCP。

### 自架 boring-registry

* Good: 資料不出自有或客戶環境。
* Bad: 要自己維運服務與認證，CI 要在打 tag 後打包上傳；對 8 個 module 來說太重。

### 一個 module 一個 repo

* Good: tag 天然就是單純的 `v1.0.0`，權限可以逐 repo 控管。
* Bad: 8 個 repo 要各自維護 CI、CODEOWNERS 與 release 設定，跨 module 的修改要開多個 PR；共用的驗證腳本沒有地方放。

## More Information

* 2026-10-19 更新：消費端預設改用 HCP Terraform private registry，見 [ADR-0004](./0004-hcp-terraform-private-registry.md)。本 ADR 的發版機制（monorepo、`<module>-v<semver>` tag、release-please）不變，`git::...?ref=<tag>` 降為備案。
* 升級路徑：需要版本範圍、專案數多到手動追 patch 變成負擔、或 clone 時間影響 CI 時，改用 HCP Terraform Free（每個 module 登記一次，Source Directory 填 `modules/<name>`、Tag Prefix 填 `<name>-v`）；資料不能出自有或客戶環境時改用 boring-registry。消費端 `source` 從 `git::...?ref=<tag>` 改成 `<registry-host>/<namespace>/<name>/aws` 加 `version = "~> 1.2"`，module 程式碼不用改。
* 設計文件：[`docs/design/v1/design-docs.md`](../design/v1/design-docs.md) §3。
