---
status: "accepted"
date: 2026-10-14
decision-makers: platform team
outcome: "專案 infra 範本拆成 8 個 stack、各自一份 state，依擁有者與變動頻率拆；apply 順序 foundation、containerimage、network、iam-base、data、iam-app、loadbalancer、application，destroy 反序。IAM 拆成 iam-base（data 之前）與 iam-app（data 之後）兩個 stack。"
notes: "上游不讀下游，單向依賴。iam-base 的 RDS Proxy role 只有 trust，iam-app 才附加讀 secret 的 policy；Proxy 建立時 role 還沒有 policy 會不會失敗未實測，兩種結果的對策寫在設計文件 §5.4。state key 一律是 `<project>-<env>/<stack>/terraform.tfstate`，由 validate.sh 的 S6 檢查。"
---

# 依擁有者與變動頻率拆分 state，IAM 拆成 iam-base 與 iam-app

## Context and Problem Statement

專案 infra 如果放在同一份 state，每週換版的 ECS service 會跟一年動一次的 VPC 一起 plan：換版時 plan 掃過所有資源，出錯時影響範圍是整個專案。另一方面，客戶自管模式下，網路、資料庫、IAM 可能由客戶接手，它們不能跟我們一定自己管的服務綁在同一份 state。

問題是：**範本要拆成幾個 stack、依什麼拆、apply 順序是什麼？** 其中 IAM 有一個依賴上的難題：RDS Proxy 建立時要給 role ARN，所以 role 要在 `data` 之前存在；但 role 讀 DB secret 的 policy，Resource 要指到 master secret 的 ARN，要等 `data` 建好才有。

## Decision Drivers

* 拆分依據要簡單、可說明：不用逐個資源爭論該放哪。
* 換版 plan 不掃過低頻資源，出錯時影響範圍小。
* 客戶自管某個 stack 時，下游不用改。
* 依賴方向單向，apply 順序就是依賴順序。
* 權限審查集中在少數地方；module 不建 IAM（客戶 deploy role 可能不能改 IAM）。

## Considered Options

* 依擁有者與變動頻率拆成 8 個 stack，IAM 拆成 iam-base 與 iam-app
* 8 個 stack，但 IAM 只有一個 stack，Proxy 的 policy 用 secret 名稱規則限定 Resource
* 單一 state，用 module 分層
* 每個環境一份大 state，只拆 application 出來

## Decision Outcome

Chosen option: 「依擁有者與變動頻率拆成 8 個 stack，IAM 拆成 iam-base 與 iam-app」，因為只有這個方案同時滿足依賴方向單向、policy 的 Resource 精確到單一 secret ARN、而且客戶可以只接手其中幾個 stack。

拆分的依據只有兩個：

1. 擁有者：誰有權改、誰負責。客戶可能接手的（網路、資料庫、IAM）跟我們一定自己管的（服務）分開。
2. 變動頻率：每週換版的不要跟一年動一次的放在一起。

apply 順序（destroy 反序）：

| 順序 | stack | 放什麼 | 變動頻率 |
|---|---|---|---|
| 1 | `foundation` | 告警 SNS、共用 KMS key、secret 容器、flow log 與 ALB access log bucket | 低 |
| 2 | `containerimage` | ECR repository；服務清單的單一決定點 | 低 |
| 3 | `network` | VPC、各層 security group | 低 |
| 4 | `iam-base` | ECS execution role、RDS Proxy role（只有 trust）、Enhanced Monitoring role | 低 |
| 5 | `data` | 資料庫（可選 Proxy）與資料庫告警 | 低 |
| 6 | `iam-app` | Proxy role 讀 secret 的 policy、各服務 task role、ECS Exec 開關 | 低到中 |
| 7 | `loadbalancer` | ALB、listener、ELB 5xx 告警、WAF 關聯 | 低到中 |
| 8 | `application` | ECS cluster、service、autoscaling、服務告警 | 高 |

IAM 拆成兩個的理由：

| stack | 時間點 | 原因 |
|---|---|---|
| `iam-base` | `data` 之前 | RDS Proxy 與 Enhanced Monitoring 建立時要 role ARN，role 必須先存在；Proxy role 只有 trust，沒有 policy |
| `iam-app` | `data` 之後 | 讀 DB secret 的 policy 要指到 master secret 的 ARN，要等 `data` 建好才寫得出 Resource；task role 的 `data_access` 權限也在這裡 |

### Consequences

* Good: 換版只 plan `application`，影響範圍小；客戶可以接手任何低頻 stack。
* Good: 權限審查只看 `iam-base`、`iam-app` 兩處。
* Bad: stack 多，要手動依序 apply 8 次。不提供 `stacks.sh`：沒有測試保護的順序腳本，很容易在增減 stack 後跟實際順序脫節，比照順序手動跑更不可靠。順序寫在範本的 `infra/README.md`。
* Bad: 第一次部署時，Proxy 建立到 `iam-app` apply 之間 Proxy 讀不到 secret；建立當下是否失敗未實測。
* Neutral: 跨 stack 的值只經 SSM 傳遞，見 [ADR-0003](./0003-cross-stack-values-via-ssm-only.md)。

### Confirmation

每個 stack 的 `terraform test`（mock provider）鎖住它讀取的 SSM key 清單；`scripts/validate.sh` 的 S6 檢查每份 `envs/<env>.tfbackend` 的 `key` 等於 `<project>-<env>/<stack>/terraform.tfstate`，避免 key 寫錯讀到別的環境的 state。

## Pros and Cons of the Options

### 8 個 stack，IAM 拆成 iam-base 與 iam-app

* Good: 依賴單向；policy 的 Resource 精確。
* Bad: 比 7 個 stack 多一個要 apply。

### 8 個 stack，IAM 只有一個 stack

* Good: 少一個 stack。
* Bad: IAM 要放在 `data` 之前，Proxy 的 policy 寫不出單一 secret ARN，只能用名稱規則放寬 Resource，違反最小權限；放在 `data` 之後則 Proxy 建立時沒有 role。

### 單一 state，用 module 分層

* Good: 一次 apply，沒有跨 stack 傳值。
* Bad: 每次換版都 plan 全部；任何一個資源出錯都擋住整個專案；客戶無法只接手其中一層。

### 每個環境一份大 state，只拆 application

* Good: 只有兩份 state，簡單。
* Bad: 網路、資料庫、IAM 仍混在一起，擁有者不同的資源沒有分開，客戶自管時要整份切開。

## More Information

* 這個拆法參考 project-a 的 stack 拆法；範本另外把 IAM 拆成 `iam-base` 與 `iam-app`。
* 設計文件：[`docs/design/v1/design-docs.md`](../design/v1/design-docs.md) §5.2、§5.3、§5.4、§5.5。
