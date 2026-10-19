---
status: "accepted"
date: 2026-10-19
decision-makers: platform team
outcome: "消費端預設改用 HCP Terraform private registry：`source = \"app.terraform.io/<org>/<module>/aws\"` 加 `version = \"~> <MAJOR>.<MINOR>.0\"`。發版機制不變（monorepo、`<module>-v<semver>` tag、release-please），HCP 用 Source Directory `modules/<module>` 與 Tag Prefix `<module>-v` 從同一批 tag 發佈。`git::...?ref=<tag>` 留作沒有 HCP token 時的備案；`vendor-modules.sh` 兩種寫法都能 vendoring。"
notes: "補充 ADR-0001 的消費端寫法，不取代它的發版機制。HCP 的 module 登記可以用 API 批次做：官方文件沒寫 `tag-prefix` 與 `source-directory`，但 API 實際接受（2026-10-19 用 26 個 module 驗證）。Free 方案的現況各方說法不一，開 org 時以 HashiCorp 官方定價頁為準。"
---

# 消費端改用 HCP Terraform private registry

## Context and Problem Statement

[ADR-0001](./0001-git-tag-monorepo-as-private-registry.md) 選了「Git tag monorepo」，消費端用 `git::https://github.com/<org>/<repo>.git//modules/<module>?ref=<module>-v<semver>` 引用，並寫好升級條件：需要版本範圍、手動追 patch 變成負擔、或 clone 時間影響 CI 時，改用 HCP Terraform。

現在 repo 已經推上 GitHub，26 個 module 都打好 tag（19 個 `v0.1.0`、10 個 `v0.1.1`）。範本複製出去時要把 56 個 `source` 逐一釘到正確的 tag，其中 10 個 module 必須是 `v0.1.1`，釘錯就 init 或 plan 失敗；之後每個 patch 版都要每個專案各開一個改 `ref` 的 PR。

問題是：**消費端要不要從 git source 換成真的 module registry？換的話，原本的 git source 跟客戶交付怎麼辦？**

## Decision Drivers

* 消費端要能寫版本範圍，patch 版用 `terraform init -upgrade` 就吃得到。
* 發版流程（release-please、tag 格式、CHANGELOG）不要因此重做。
* module 程式碼與目錄不動。
* 客戶環境不一定連得到外部服務，也不能拿到我們的 token；FDE 的 vendoring 不能斷。
* 不想自己維運一個 registry 服務。

## Considered Options

* HCP Terraform private registry，git source 留作備案
* 只用 HCP Terraform，拿掉 git source
* 自架 registry（boring-registry、Terrareg）
* 公開 Terraform Registry（registry.terraform.io）
* 維持 git source

## Decision Outcome

Chosen option: 「HCP Terraform private registry，git source 留作備案」，因為現有 tag 格式就是照 HCP 的 Tag Prefix 設計的，發版流程與 module 都不用改，消費端換得到版本範圍；git source 保留給拿不到 HCP token 的人，FDE 交付也不受影響。

消費端寫法：

```hcl
module "api" {
  source  = "app.terraform.io/<org>/ecs-service/aws"
  version = "~> 0.1.0"
}
```

* `<org>` 是 HCP Terraform 的 organization 名稱。module 名稱與目錄名稱相同，provider 一律填 `aws`。
* 0.x 期間 MINOR 可能是破壞性變更（設計文件 §3.5），所以約束寫到 PATCH（`~> 0.1.0`，等於 `>= 0.1.0, < 0.2.0`）。到 1.0 之後改成 `~> 1.2`。
* HCP 的每個 module 都登記成 tag-based 發佈：Source Directory 填 `modules/<module>`，Module Tag Prefix 填 `<module>-v`。tag `s3-bucket-v0.1.1` 會發佈成 `s3-bucket` 的 `0.1.1`。
* 範本在本 repo 裡仍用相對路徑（設計文件決策 #2 不變），CI 驗的是當下的 module 程式碼；複製出去時換成 registry 寫法，指令見 [`consuming-modules.md`](../guides/consuming-modules.md)。

### Consequences

* Good: 有版本範圍；patch 版不用每個專案開 PR，`init -upgrade` 就吃得到。
* Good: 範本複製出去時每個 module 都寫 `~> 0.1.0`，不必記哪 10 個要釘 `v0.1.1`。
* Good: 發版流程、tag、CHANGELOG、module 程式碼都不變；HCP 透過 webhook 讀新 tag。
* Bad: 多了一層憑證。消費端與 CI 要有 HCP token（`terraform login` 或 `TF_TOKEN_app_terraform_io`），這是 ADR-0001 刻意避開的。
* Bad: 多一個外部依賴。HCP 掛掉或 token 過期時 `terraform init` 抓不到 module；已經 init 過的 `.terraform/modules` 不受影響，必要時退回 git source。
* Bad: 每個 module 都要在 HCP 登記一次，新增 module 時也要記得登記（[`hcp-registry-setup.md`](../guides/hcp-registry-setup.md) 有網頁與 API 兩種做法）。登記用的 API 欄位不在官方文件裡，HCP 改版時可能要改回網頁登記。
* Bad: 有版本範圍代表 `init -upgrade` 可能吃到新的 patch 版。PATCH 必須真的不改 plan，這條規則照舊由 platform team 在 review 時把關。
* Neutral: `vendor-modules.sh` 改成兩種寫法都認得。registry 寫法沒有 tag 可以直接比對，改讀 `terraform init` 寫下的 `modules.json`，以 Terraform 實際解析到的版本為準。

### Confirmation

* `scripts/vendor-modules.sh --registry <host>/<namespace>` 只改寫「source 是 `<host>/<namespace>/<module>/aws`，而且 `modules.json` 解析到的版本等於指定 tag」的 module 區塊，同時拿掉該區塊的 `version`；版本不同或沒有 init 過的區塊不動並列出來，結束碼 3。
* HCP 上的版本清單要跟 GitHub 的 tag 對得上：登記完之後照 [`hcp-registry-setup.md`](../guides/hcp-registry-setup.md) 的檢查步驟，對每個 module 跑一次 `terraform init`。
* 本 repo 的 CI 不連 HCP，驗的仍是當下的程式碼。

## Pros and Cons of the Options

### HCP Terraform private registry，git source 留作備案

* Good: 見上方 Consequences。
* Bad: 文件要同時說明兩種寫法。

### 只用 HCP Terraform，拿掉 git source

* Good: 文件只有一種寫法。
* Bad: 沒有 HCP token 的讀者（這個 repo 是公開範例）與客戶環境就沒有路可走；HCP 出問題時沒有退路。

### 自架 registry（boring-registry、Terrareg）

* Good: 資料不出自有環境。
* Bad: 要維運一個服務。registry 的下載端點要回 `204` 加 `X-Terraform-Get` header，純靜態網站做不到（從協定文件推論）；CI 還要在打 tag 後打包上傳。目前沒有「資料不能出自有環境」的需求。

### 公開 Terraform Registry

* Good: 不用帳號、不用 token。
* Bad: 一個 module 要一個 repo，名稱要是 `terraform-aws-<name>`，tag 要是 `v1.2.3`；monorepo 與 `<module>-v` tag 都要放棄，ADR-0001 的發版機制全部重做。

### 維持 git source

* Good: 不多一層憑證與外部依賴。
* Bad: 沒有版本範圍，範本複製出去要逐個 module 釘 tag，每個 patch 版每個專案都要開 PR。

## More Information

* 協定：消費端的 `<host>/<namespace>/<name>/<system>` 會先打 `https://<host>/.well-known/terraform.json` 做 service discovery，再用 `modules.v1` 端點列版本與下載（[module registry protocol](https://developer.hashicorp.com/terraform/internals/module-registry-protocol)）。
* HCP 的發佈設定：[Publish modules to the HCP Terraform private registry](https://developer.hashicorp.com/terraform/cloud-docs/registry/publish-modules)。「從單一 repo 發佈多個 module」在 HCP SaaS 的文件上沒有標 beta、預設開啟；Terraform Enterprise 1.2.x 的文件曾標 beta。
* 何時重新檢討：HCP 的方案或價格改到不划算、或出現「資料不能出自有環境」的消費端時，改評估自架 registry；消費端只改 `source` 的 host 與 namespace。
