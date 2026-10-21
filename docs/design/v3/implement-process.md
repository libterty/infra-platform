# infra-platform v3 實作流程：EC2、EKS、權重分流與斷路器

> 狀態：草案，等 [`design-docs.md`](./design-docs.md) 審過才開始。這份只講「一步一步怎麼做、每步怎麼驗收」；兩份衝突時以 design-docs.md 為準，回頭改這份。
> 文中路徑除非特別註明，都是 repo 內相對路徑。「design §x.y」指 design-docs.md 的章節。

## 結論

這次只有 module，沒有範本，一個里程碑分 8 個 Phase，每個 Phase 一層 stacked PR（`gh stack`）：A0 先改 `validate.sh`，接著擴充既有 module、新 module、共用設定，最後發版與 HCP 登記。範本整合（design §5）之後另開里程碑，而且 module 發版、HCP 登記完才能開始。

一次做一個 Phase，主 agent 自己重跑驗收通過後 commit 並 `gh stack submit`，才進下一個；每個 Phase 結束先跟使用者確認，再往下。一個 module 一個 commit。

## 限制（每個 Phase、每個 subagent 都適用）

- Terraform 只准跑 `init -backend=false` 與建在它上面的 `validate`、搭配 `mock_provider` 的 `test`。`scripts/validate.sh` 就是這樣跑的，而且會清掉 AWS 環境變數（A0 之後也清 `KUBECONFIG`、`KUBE_*`、`HELM_*`）。
- 不准連 AWS 或任何 Kubernetes 叢集；不准 `plan`、`apply`、帶 `-backend-config` 的 `init`、`terraform providers lock`、`helm install`、`kubectl`。`helm lint` 與 `helm template` 可以。
- 不准 build 或推 Docker 映像。
- code、tfvars、tests、註解、commit message 只出現 `dev`、`sit` 兩個環境名稱。
- 佔位值照 [`../v2/integration-playbook.md`](../v2/integration-playbook.md) §2：帳號 `111111111111`、網段 `10.10.0.0/16`、網域 `example.com`。
- 研究報告標「未確認」的行為（design §6），tests 不能當成事實斷言；能用 validation 擋的才擋，其他寫進 README 的「注意」。
- commit 在 feature branch 上做，不推 `main`；push、打 tag、建 Release、HCP 登記之前先問使用者。

## Phase 表

| Phase | 內容 | 狀態 | commit |
|---|---|---|---|
| 0 | v3 設計文件與實作流程 | 草案，等審閱 | — |
| A0 | `validate.sh`：S4-a 允許 `iam-oidc-provider`、S1 改成依 `required_providers` 檢查 mock、清 Kubernetes 與 Helm 的環境變數、有 `helm` 時 lint 本地 chart、有 `python3` 時跑 Lambda 的 unittest | 完成：fixture 8 個情境 RED→GREEN；全量 91 個目錄通過 | `f274f3f` |
| A1 | 擴充既有 module：`iam-role` 0.3.0、`alb` 0.4.0、`vpc` 0.2.0；`lambda-function` 補測試 | 完成：既有 tests 不改全過；iam-role 67、alb 109、vpc 74、lambda-function 100 個 run 全過 | `8e8458f..0a4e84a` |
| A2 | 新 module：`ec2-instance`、`ec2-asg` | 未開始 | — |
| A3 | 新 module：`nlb`、`lb-traffic-breaker`（含 Lambda 程式碼與 Dockerfile） | 未開始 | — |
| A4 | 新 module：`iam-oidc-provider`、`eks-iam-policies`、`eks-cluster` | 未開始 | — |
| A5 | 新 module：`eks-addons`（helm provider、本地 chart） | 未開始 | — |
| A6 | 共用設定：release-please config 與 manifest、README module 表與徽章、CHANGELOG、guides | 未開始 | — |
| A7 | （使用者確認後）合併、打 8 個新 module 的 tag、補 GitHub Release、HCP 登記；擴充的 3 個走 release-please | 未開始 | — |

## 每個 Phase 的做法與驗收

### A0：`validate.sh`

改法見 design §4.3。先在 scratchpad 做 fixture，確認舊版漏掉、新版抓到（RED → GREEN）：

1. 一個不在允許清單裡的 module 寫了 `aws_iam_openid_connect_provider`：要被 S4-a 擋。`modules/iam-oidc-provider/` 寫同一個 resource：要通過。
2. 一個 `required_providers` 只有 helm 的 module，測試檔只宣告 `mock_provider "aws"`：要被 S1 擋。宣告 `mock_provider "helm"`：要通過。
3. 設了 `KUBECONFIG` 的環境下跑：腳本執行時要看不到這個變數。
4. 有語法錯誤的本地 chart：有裝 `helm` 時要失敗，沒裝時跳過並印出提示。

驗收：

- fixture 四個情境的結果如上。
- 全量 `scripts/validate.sh` 的目錄數與結果跟改之前相同。
- `bash -n`、`shellcheck` 通過。

### A1：擴充既有 module

介面見 design §4.1。每個 module：

1. 先寫新的 tests（RED）：新功能的 run 因為還沒實作而失敗；新 validation 各有正反兩個 run。
2. 寫最小實作讓 tests 通過（GREEN），再整理（REFACTOR）。
3. 既有 tests 一個都不改。
4. README 補新變數與「注意」。CHANGELOG 不要手改：這 3 個 module 走 release-please，版本段落由它產生（[`releasing-modules.md`](../../guides/releasing-modules.md)）。commit 用 `feat(<module>): ...`，message 寫清楚消費端 plan 會看到什麼。
5. commit：`feat(<module>): <what>`；`lambda-function` 只補測試，用 `test(lambda-function): <what>`。

必寫的安全負向測試：

- `iam-role`：白名單外的 managed policy 被拒；`federated` 與 `service_principals` 同時給被拒。
- `alb`：權重全 0 被拒；超過 5 個 target 被拒。

驗收：

- `scripts/validate.sh modules/<module>` 全過（含 `examples/`）。
- `git diff` 確認既有 tests 沒有變動。
- `iam-role` 的 tests 斷言：`tag_session` 預設時 trust 的 JSON 跟 0.2.0 完全相同。
- `alb` 的 tests 斷言：沒有 `forward` 時規則的 action 跟 0.3.0 完全相同。

### A2：`ec2-instance`、`ec2-asg`

介面與必寫情境見 design §4.2。每個 module 都有 `examples/basic/`、`README.md`、`CHANGELOG.md`（`## 0.1.0（未發布）`）。TDD 步驟同 A1。

必寫的安全負向測試：

- IMDSv2 固定 required，沒有輸入可以關掉（斷言 `metadata_options`）。
- 不配 public IP。
- 碟片都加密。
- `user_data` 出現像 secret 的字樣被拒。

驗收：

- `scripts/validate.sh modules/ec2-instance modules/ec2-asg` 全過，`tflint` 零警告。
- `ec2-asg` 的 `examples/` 至少有一個掛 `alb` target group 的情境。

### A3：`nlb`、`lb-traffic-breaker`

介面見 design §4.2。

`nlb` 必寫：

- 多個 target group 的 listener 沒把 `dns_failover` 設成 `"off"` 被拒（J12）。
- TLS listener 沒有憑證被拒，搭配開了 stickiness 的 target group 也被拒。
- 同一個 listener 的 protocol 不一致被拒。

`lb-traffic-breaker`：

1. 先寫 `lambda/test_breaker.py`（RED）：
   - ALB rule 與 NLB listener 的 describe 結果，算出「stable 有權重、其他 0」的完整 action 清單。
   - 已經切過的情況回傳「不用改」（冪等）。
   - 保留 stickiness 設定。
   - stable target group 不在 forward 裡時回錯。
   - `BREAKER_CONFIG` 的 schema 版本不認得時回錯。
2. 寫 `breaker.py` 讓 unittest 通過（只用標準函式庫），再寫 `handler.py` 的 boto3 薄殼與 `Dockerfile`。
3. Terraform 的 tests：
   - ALB 建兩條 alarm、NLB 只建健康主機數。
   - NLB 給 5xx 參數被拒。
   - `listener_arn` 與 `rule_arn` 擇一。
   - alarm action 同時有 Lambda 與 SNS。
   - `treat_missing_data` 依訊號不同。
   - `lambda_permissions` 的 `source_arn` 與 alarm ARN 一致。

驗收：

- `scripts/validate.sh modules/nlb modules/lb-traffic-breaker` 全過。
- `python3 -m unittest` 全過。
- README 有 ALB 與 NLB 的差異表、build 映像的指令、design §5 的 runbook。

### A4：`iam-oidc-provider`、`eks-iam-policies`、`eks-cluster`

介面見 design §4.2。`eks-cluster` 的 tests 依主題拆檔，每個檔在 800 行內：

- 叢集設定
- 節點模式與互斥
- add-on
- access entry
- Karpenter 的 AWS 資源

必寫：

- 固定值三項（J3）與 secrets 加密。
- J2 的每條互斥規則正反各一；Auto Mode 加 Fargate 要能通過（D17）。
- `eks-iam-policies`：輸出是合法 JSON，Karpenter 的 `iam:PassRole` 只限 node role，不支援的版本被拒。
- 沒有 cluster admin 的 access entry 被拒。
- public endpoint 給 `0.0.0.0/0` 被拒。
- launch template 的 IMDSv2 與 EBS 加密。

驗收：

- `scripts/validate.sh modules/iam-oidc-provider modules/eks-cluster` 全過。
- `examples/` 至少三個：managed node group 加 Karpenter、Auto Mode、managed node group 加 Fargate。

### A5：`eks-addons`

介面見 design §4.2。tests 用 `mock_provider "helm"`；本地 chart 放 `charts/`。

必寫：

- 物件為 null 時沒有 release。
- Karpenter 的必要設定有傳。
- `default_node_pool = null` 時不裝本地 chart。
- LB Controller 有 `region` 與 `vpc_id`。

驗收：

- `scripts/validate.sh modules/eks-addons` 全過。
- 有裝 `helm` 時 `helm lint`、`helm template` 通過。
- README 有 provider 設定範例（`exec` 跑 `aws eks get-token`）與 CI 用 Helm 部署的權限說明。

### A6：共用設定

- `release-please-config.json` 加 7 個 package；`.release-please-manifest.json` 加 7 個 `"0.1.0"`。擴充的 3 個不手改 manifest，交給 release-please。
- `README.md` 的 module 表加 8 列與「EKS」分類，`共 32 個 module` 改成 40。
- `docs/guides/releasing-modules.md` 補上 helm provider 的 module 怎麼測；`docs/guides/consuming-modules.md` 補上 `eks-addons` 的 provider 設定。

驗收：

- 全量 `scripts/validate.sh` 通過。
- 這個 stack 每一層的 CI 都綠燈。

### A7：發版與 HCP 登記

每一步做之前先問使用者：

1. 依序合併 stack 的每一層。擴充的 3 個 module 的 `feat` commit 進 `main` 後，release-please 會開 release PR。看過 diff（release PR 不會觸發 CI）再合併，tag 由 release-please 打。
2. 8 個新 module：先在 PR 裡把 CHANGELOG 的「（未發布）」改成發版日期，合併後打 annotated tag，**一次最多 push 3 個**，分 3 批。
3. `gh release create <tag> --notes-file modules/<m>/CHANGELOG.md`，不設 latest。
4. 照 `docs/guides/hcp-registry-setup.md` §3 登記 8 個新 module，等狀態變成 `setup_complete`。
5. 確認擴充的 3 個 module 在 HCP 上有新版本。沒有就照〈之後的維護〉補。

驗收：照 `hcp-registry-setup.md` §4 在暫存目錄 `terraform init -backend=false` 抓 40 個 module，版本跟 tag 一致。
