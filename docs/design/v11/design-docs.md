# infra-platform v11 設計文件：CI/CD module 與 templates/example9

> 狀態：已實作（2026-10-30，L0–L7，見 [`implement-process.md`](./implement-process.md)）。實作時跟設計不同的決定記在 §14，兩邊不同時以 §14 與程式碼為準。§3.1 的 D 是使用者拍板的決策；§3.2 的 K 是照慣例的判斷，審閱時可以推翻。標「審閱重點」的是需要特別看的取捨。
> 範圍：新增 AWS CI/CD 用的 module（CodeConnections、CodeBuild、CodePipeline），三個既有 module 升 minor（`ecs-service`、`lambda-function`、`iam-role`），新建範本 `templates/example9`。不改 example2–example6、account-baseline、project-infra。
> 文中路徑除非特別註明，都是 repo 內相對路徑。provider schema 是 aws 6.70.0（`terraform providers schema -json`）的結果。標「未確認」的要在實作或真實環境驗證。環境只有 `dev`、`sit`。

## 1. 結論

- **新 module 3 個**，每個發 0.1.0、在 HCP 登記。repo 的 module 從 91 個變成 94 個：
  - `codeconnections-connection`：連到 GitHub 的 connection。
  - `codebuild-project`：給 pipeline 呼叫的建置專案。
  - `codepipeline`：V2 pipeline。
- **不做 CodeDeploy module**（§2 第 2、3 點）：
  - Lambda 的 canary 與 linear 由 CodePipeline V2 的 Lambda 部署 action 直接做。
  - ECS 的 blue/green 用 ECS 原生的部署策略。
- **既有 module 升 minor 3 個**，只加輸入，預設值行為不變：
  - `ecs-service` 0.2.1 → 0.3.0：讓 pipeline 管 task definition，並支援原生 blue/green。
  - `lambda-function` 0.1.1 → 0.2.0：發布版本、建 alias，讓 pipeline 管程式碼版本。
  - `iam-role` 0.5.0 → 0.6.0：白名單加 ECS 管 ALB 用的 AWS managed policy。
- **新範本 `templates/example9`（D5）**：
  - 每個環境 apply 一份。內容是一個 ECS API、一個 Lambda、一個 S3 加 CloudFront 的前端，加上部署這三個元件的三條 pipeline。
  - 8 個 stack（§8）。
- **pipeline 只能手動執行（D7）**：source action 關掉 change detection，不建 trigger。
- **Phase**：L0–L7（§12）。module 先做（L1–L3），全部在 HCP 上之後才做範本（L4–L7）。

## 2. 查證發現

1. **aws 6.70.0 都有對應 resource**：`aws_codeconnections_connection`、`aws_codebuild_project`、`aws_codepipeline`（有 `pipeline_type`、`trigger`、`variable`、`execution_mode`）。都有 resource 層級的 `region`。不需要 awscc。
2. **Lambda 部署 action 不需要 CodeDeploy**（CodePipeline 文件）：
   - 只有 V2 pipeline 能用。
   - `DeployStrategy` 可以是 `AllAtOnce`、`Canary10Percent5Minutes`、`Linear10PercentEvery1Minute` 這類格式，百分比與分鐘數可以改，總等待時間上限 2 天。
   - 要先有 alias，alias 後面要有一個已發布的版本（rollback 的目標）。
   - 沒有 input artifact 時，用 `PublishedTargetVersion` 只切流量。容器映像檔的函式就用這種方式：CodeBuild 先更新映像檔並發布版本，再由這個 action 切 alias。
   - `Alarms` 最多 10 個，進入 ALARM 時 action 失敗。
3. **ECS 原生 blue/green**（ECS 文件，2025 年推出）：
   - service 的 deployment controller 要是 `ECS`，`deployment_configuration.strategy = "BLUE_GREEN"`，可設 `bake_time_in_minutes`。
   - ALB 要兩個 target group；`load_balancer.advanced_configuration` 要給 `alternate_target_group_arn`、`production_listener_rule`、`role_arn`，`test_listener_rule` 選填。
   - `role_arn` 是讓 ECS 改 ALB 的 role，AWS managed policy 是 `AmazonECSInfrastructureRolePolicyForLoadBalancers`。
   - 部署時 ECS 會改 production listener rule 兩個 target group 的權重。
   - provider 6.70.0 的 `strategy` 另外還有 canary、linear 的設定區塊。
4. **CodePipeline 的 ECS 標準 action 會複製 service 目前用的 task definition**（CodePipeline 文件）：只換映像檔。Terraform 另外註冊的新版本，在 service 沒有改用之前會被忽略。所以如果用這個 action，Terraform 改的環境變數、secret、CPU 永遠進不了部署（§5.4，審閱重點）。
5. **V2 pipeline 的計價**：每分鐘 action 執行時間 0.002 美元，每個帳號每月前 100 分鐘免費；manual approval 不計費。
6. **CodeConnections**：connection 建好後狀態是 `PENDING`，要有人在 AWS console 按一次授權（GitHub App 安裝）才會變 `AVAILABLE`。這一步不能用 Terraform 完成。
7. **source action 的 change detection**：`CodeStarSourceConnection` 的 `DetectChanges` 預設是 `true`，V2 pipeline 會依它自動觸發（未確認：沒有 `trigger` 區塊時 V2 的實際行為，L2 查文件確認）。D7 要手動執行，所以 module 固定 `DetectChanges = "false"`、不建 `trigger`。

## 3. 決策

### 3.1 使用者拍板（2026-10-29）

| # | 決策 |
|---|---|
| D1 | 程式碼放 GitHub，透過 CodeConnections 連線 |
| D2 | 部署目標：ECS、Lambda、S3 加 CloudFront 前端 |
| D3 | dev 與 sit 各自在自己的帳號；pipeline 跟部署目標在同一個帳號，不做跨帳號部署 |
| D4 | pipeline 只部署應用程式；基礎設施照舊由 HCP Terraform 管 |
| D5 | 新範本叫 `templates/example9`，示範公司的 CI/CD pipeline |
| D6 | 應用程式版本由 pipeline 管：Terraform 只建第一版，之後忽略映像檔與 Lambda 版本的變動 |
| D7 | pipeline 不自動觸發，只能手動執行 |
| D8 | `ecs-service` 支援 rolling 與原生 blue/green；範本用 rolling 示範，blue/green 由 module 測試覆蓋 |
| D9 | Lambda 用容器映像檔 |

### 3.2 照慣例的判斷（審閱時可以推翻）

| # | 判斷 | 理由 |
|---|---|---|
| K1 | 不做 CodeDeploy module | §2 第 2、3 點；ECS 與 Lambda 都有不靠 CodeDeploy 的做法，EC2 ASG 不在 D2 的範圍 |
| K2 | `codebuild-project` 只支援 `CODEPIPELINE` 類型的 source 與 artifact | D7 只從 pipeline 執行；不做 webhook、不讓 CodeBuild 自己連 GitHub，連線權限只在 pipeline role |
| K3 | ECS 的部署由 CodeBuild 做，不用 CodePipeline 的 ECS 標準 action | §2 第 4 點；見 §5.4 |
| K4 | 每個元件一條 pipeline（api、fn、web），都指向同一個 repo 與分支，buildspec 路徑不同 | 三個元件可以各自部署、各自失敗；一條 pipeline 平行三個 action 時，任何一個失敗整條要重跑 |
| K5 | buildspec 放在應用程式 repo；範本只給路徑，REFERENCE 附三份範例 | buildspec 跟著程式碼改；放在 Terraform 裡每次調整建置都要 apply |
| K6 | sit 的 pipeline 部署前加 manual approval；dev 不加 | 手動執行已經是一道關卡，但 sit 多一道確認可以避免在錯的環境按到執行（manual approval 不計費） |
| K7 | pipeline 失敗用既有 `eventbridge-rule` 送到告警 SNS，不用 CodeStar Notifications | 跟 v10 K13 一樣，不另外接通知管道 |
| K8 | artifact bucket 用 `s3-bucket`、CMK 加密、30 天過期 | artifact 只在一次執行內有用 |
| K9 | CodeBuild 預設 `BUILD_GENERAL1_SMALL` ARM（`arm1.small` 類）、`aws/codebuild/amazonlinux-aarch64-standard` 映像；建映像檔的專案開 `privileged_mode` | 免費額度涵蓋 small；ECS 與 Lambda 範本都用 ARM64 |
| K10 | 第一次部署前，映像檔由人手動推一次 | 跟 example6 一樣：Lambda 建立時映像檔一定要存在；ECS service 沒有映像檔會一直拉不到 |
| K11 | Phase 代號用 L（K 已用在這張表） | 接在 v10 的 J 之後 |

## 4. trust boundary 與特權操作

| 邊界 | 誰跨過 | 控制 |
|---|---|---|
| GitHub → AWS | CodeConnections | GitHub App 只裝在指定的 repo；pipeline role 的 `codeconnections:UseConnection` 只給這一個 connection ARN |
| pipeline → CodeBuild | CodePipeline | pipeline role 只能 `StartBuild`、`BatchGetBuilds` 這幾個專案 |
| CodeBuild → ECR | 建置專案 | 只能推到自己元件的 repository |
| CodeBuild → ECS | api 的部署專案 | `RegisterTaskDefinition`、`UpdateService`、`DescribeServices` 只給這個 service；`iam:PassRole` 只給這個 service 的 execution role 與 task role，條件 `iam:PassedToService = ecs-tasks.amazonaws.com` |
| CodeBuild → Lambda | fn 的建置專案 | `UpdateFunctionCode`、`PublishVersion`、`GetFunction` 只給這個函式 |
| pipeline → Lambda | Lambda 部署 action | `UpdateAlias`、`GetAlias` 等只給這個函式與 alias |
| CodeBuild → S3、CloudFront | web 的建置專案 | 只能寫前端 bucket；`CreateInvalidation` 只給這個 distribution |
| 人 → pipeline | 開發者 | 誰能按「執行」由 IAM 決定，不在範本範圍；REFERENCE 列出需要的 action |

### 4.1 CodeBuild 的權限範圍（審閱重點）

- 建置專案會跑應用程式 repo 裡的 buildspec，等於 repo 的寫入者可以用 CodeBuild role 的權限做任何事。
- 範本的做法：
  - 每個元件一個建置 role，彼此不共用（§4 表格）。
  - 建置 role 不能讀 Secrets Manager。需要建置用的 secret 時，在 `codebuild-project` 的 `environment_variables` 用 `SECRETS_MANAGER` 類型，並在 iam stack 明確給那一個 secret。
  - 建置專案不放進 VPC。專案不需要連內部資源，放進 VPC 反而要開 NAT 的對外連線。
- 所以 GitHub repo 的 branch protection 是這條信任鏈的一部分。REFERENCE 寫清楚：被部署的分支只能透過 PR 合併。

## 5. module 清單

| module | provider | resource | 用在 example9 |
|---|---|---|---|
| `codeconnections-connection` | aws | `aws_codeconnections_connection` | `foundation` |
| `codebuild-project` | aws | `aws_codebuild_project` | `pipeline` |
| `codepipeline` | aws | `aws_codepipeline` | `pipeline` |

共用的規則跟 v10 一樣：

- 不建 IAM 與 security group（S4），不用 `random_password`（S7）。
- `description` 用台灣繁體中文，註解與 `error_message` 用英文。
- README 表格由 terraform-docs 產生（S11），每個 module 有 `examples/basic` 與 `tests/`。
- regional 的 module 都收 `region`（`null` 用 provider 的 region）。

### 5.1 `codeconnections-connection`

- 責任：一個 connection。
- 輸入：`name`（1–32 字元）、`provider_type`（`GitHub`、`GitHubEnterpriseServer`、`GitLab`、`GitLabSelfManaged`、`Bitbucket`，預設 `GitHub`）、`host_arn`（自架版本才需要）、`region`、`tags`。
- validation：名稱長度；自架類型必須給 `host_arn`，雲端類型不能給。
- 輸出：`arn`、`status`。README 寫清楚 `PENDING` 要到 console 授權。
- 刻意不做：`aws_codeconnections_host`（自架 GitHub Enterprise 或 GitLab 的 host）。

### 5.2 `codebuild-project`

- 責任：一個給 pipeline 用的建置專案。
- 輸入：
  - `name`、`description`、`service_role_arn`（必填）。
  - `buildspec`：source repo 裡的路徑，或 inline YAML。
  - `environment = { compute_type, image, type, privileged_mode }`，預設照 K9。
  - `environment_variables`：名稱 → `{ value, type }`，`type` 是 `PLAINTEXT`、`PARAMETER_STORE`、`SECRETS_MANAGER`。
  - `encryption_key_arn`（必填，只收 key ARN）。
  - `log_group_name`、`log_retention_days`、`log_kms_key_arn`：module 自己建 log group，跟 `lambda-function` 一樣。
  - `build_timeout`（預設 30 分鐘）、`queued_timeout`（預設 60 分鐘）、`concurrent_build_limit`（預設 1）。
  - `cache_modes`：預設 `["LOCAL_DOCKER_LAYER_CACHE", "LOCAL_SOURCE_CACHE"]`。
  - `region`、`tags`。
- 固定：`source.type = "CODEPIPELINE"`、`artifacts.type = "CODEPIPELINE"`、CloudWatch Logs 開、S3 log 關、`project_visibility = "PRIVATE"`。
- validation：
  - `PLAINTEXT` 的變數名稱不能像 secret（含 `PASSWORD`、`SECRET`、`TOKEN`、`KEY`），要用另外兩種類型。
  - `compute_type` 與 `type` 要搭配（ARM 映像配 `ARM_CONTAINER`）。
  - KMS 與 role 的 ARN 格式；`build_timeout` 5–2160 分鐘。
- 輸出：`name`、`arn`、`log_group_name`。
- 刻意不做：webhook 與 GitHub 直連（K2）、batch build、reserved fleet、VPC 設定、report group、Lambda compute。

### 5.3 `codepipeline`

- 責任：一條 V2 pipeline。
- 輸入：
  - `name`、`role_arn`、`artifact_bucket_name`、`artifact_kms_key_arn`（必填）。
  - `source = { connection_arn, repository, branch }`：module 產生 `CodeStarSourceConnection` 的 source stage，固定 `DetectChanges = "false"`、`OutputArtifactFormat = "CODE_ZIP"`。
  - `stages`：source 之後的 stage 清單，每個 stage 有 `name` 與 `actions`。action 欄位照 provider（`category`、`provider`、`configuration`、`input_artifacts`、`output_artifacts`、`namespace`、`run_order`），`owner` 固定 `AWS`、`version` 固定 `1`。
  - `variables`：pipeline 層級變數。
  - `execution_mode`：預設 `QUEUED`。
  - `region`、`tags`。
- 固定：`pipeline_type = "V2"`；不建 `trigger`（D7）。
- validation：
  - action 的 `category` 只收 `Approval`、`Build`、`Deploy`、`Invoke`、`Test`；source stage 由 module 產生，`stages` 裡不能再放 `Source`。
  - `repository` 是 `owner/name` 格式；KMS 與 role 的 ARN 格式。
  - stage 名稱不重複；至少一個 stage。
- 輸出：`name`、`arn`。
- 刻意不做：trigger（D7）、跨 region 或跨帳號 action、自訂 action type、`before_entry`、`on_success`、`on_failure` 條件（之後需要再加）。

### 5.4 `ecs-service` 0.3.0（審閱重點）

新增兩個輸入：

- `pipeline_managed`（預設 `false`）：
  - `true` 時 service 忽略 `task_definition` 的變動。Terraform 還是會在設定改變時註冊新的 task definition 版本，但不會讓 service 改用它。
  - `image` 只用在第一次建立。
- `deployment`（預設 `{ strategy = "ROLLING" }`）：
  - `strategy` 是 `ROLLING` 或 `BLUE_GREEN`，`bake_time_in_minutes` 選填。
  - `BLUE_GREEN` 時要給 `role_arn`；module 多建一個 alternate target group，service 的 `advanced_configuration` 指到 module 建的 listener rule。這只支援 module 自己建 target group 的接法（`listener_arn`）。
  - `BLUE_GREEN` 必須搭配 `pipeline_managed = true`，因為部署時 ECS 會改 listener rule 的權重，Terraform 要忽略。

**為什麼不用 CodePipeline 的 ECS 標準 action（K3）**：

- 這個 action 會複製 service 目前用的 task definition、只換映像檔（§2 第 4 點）。搭配 `pipeline_managed` 之後，Terraform 改的環境變數、secret、CPU 不會被任何部署帶上。
- 改由 CodeBuild 的部署專案做這三步：
  1. 取得 task definition family 的最新版本，也就是 Terraform 最後註冊的那一版。
  2. 換上新的映像檔，註冊成新版本。
  3. `UpdateService`。
- 這樣 Terraform 的設定變動會在下一次 pipeline 執行時一起部署；`UpdateService` 也會照 service 的部署策略走 rolling 或 blue/green。
- 代價：
  - 部署專案要等 service 穩定才結束，等待時間算 CodeBuild 的分鐘數。
  - console 上看不到 ECS action 的部署圖示。

**實作要點**：

- `lifecycle.ignore_changes` 不能用變數決定。所以 module 裡的 service 要有三個版本：預設、`pipeline_managed`、`pipeline_managed` 加 `BLUE_GREEN`，用 `count` 互斥。
- 預設版本用 `moved` 從 `aws_ecs_service.this` 搬到 `aws_ecs_service.this[0]`，既有使用者升版時不會重建。
- listener rule 一樣分成兩個版本，`BLUE_GREEN` 版本忽略 `action`。
- blue/green 部署後，service 的 `load_balancer.target_group_arn` 會不會跟 alternate 互換：未確認。如果會換，`BLUE_GREEN` 版本也要忽略 `load_balancer`，要在真實環境驗證。

### 5.5 `lambda-function` 0.2.0

新增：

- `alias`（預設 `null`）：給名稱時 module 開 `publish = true`，並建一個指向發布版本的 alias。
- `pipeline_managed`（預設 `false`）：`true` 時忽略 `image_uri` 與 alias 的 `function_version`、`routing_config`；必須搭配 `alias`。

實作方式跟 §5.4 一樣：function 與 alias 用 `count` 分兩個版本，預設版本用 `moved` 保住位址。

輸出加 `alias_arn`、`alias_name`、`version`。

### 5.6 `iam-role` 0.6.0

白名單加 `AmazonECSInfrastructureRolePolicyForLoadBalancers`（實際 ARN 路徑在 L3 查文件確認，可能在 `service-role/` 底下），給 `ecs-service` 的 blue/green 用。範本用 rolling，所以範本不會用到；放進白名單是讓採用 blue/green 的專案不用再升 `iam-role`。

## 6. 既有 module

- 照用：`vpc`、`kms-key`、`s3-bucket`、`ecr-repository`、`ecs-cluster`、`alb`、`cloudfront-distribution`、`log-group`、`sns-alarm-topic`、`eventbridge-rule`、`iam-role`、`iam-role-policy`、`ssm-publish`、`ssm-read`。
- 不改：所有既有範本。

## 7. 範本對帳號的假設

- 一個 env 一個帳號：`dev` 在 `111111111111`，`sit` 在 `222222222222`，跟其他範本的佔位一致。
- 主 region `ap-northeast-1`；CloudFront 的設定照 v9（不需要 us-east-1 的憑證，因為範本用 CloudFront 預設網域）。
- GitHub repo 佔位 `example-org/example-app`；dev 部署 `develop` 分支，sit 部署 `main` 分支（tfvars）。

## 8. templates/example9

### 8.1 stack 清單與 ORDER

```
containerimage foundation network iam loadbalancer application web pipeline
```

| # | stack | 建什麼 | 主要 module |
|---|---|---|---|
| 1 | `containerimage` | api 與 fn 的 ECR repository | `ecr-repository` |
| 2 | `foundation` | CMK、artifact bucket（30 天過期）、前端 bucket、告警 SNS topic、GitHub connection | `kms-key`、`s3-bucket`、`sns-alarm-topic`、`codeconnections-connection` |
| 3 | `network` | VPC（app tier 給 ECS 與 ALB） | `vpc` |
| 4 | `iam` | ECS execution 與 task role、Lambda role、三個建置 role、api 的部署 role、pipeline role、EventBridge 送 SNS 不需要 role | `iam-role`、`iam-role-policy` |
| 5 | `loadbalancer` | 內部 ALB（HTTP 80，VPC 內部用） | `alb` |
| 6 | `application` | ECS cluster、api service（`pipeline_managed`、rolling）、fn 函式（容器映像檔、alias `live`、`pipeline_managed`） | `ecs-cluster`、`ecs-service` 0.3.0、`lambda-function` 0.2.0 |
| 7 | `web` | CloudFront（S3 origin、OAC、SPA fallback） | `cloudfront-distribution` |
| 8 | `pipeline` | 建置專案（api build、api deploy、fn build、web build）、三條 pipeline、pipeline 失敗的 EventBridge rule | `codebuild-project`、`codepipeline`、`eventbridge-rule` |

- 照 `templates/project-infra` 的標準：只有樹 A，沒有 bridge。所有 stack 只呼叫 module，S8 沒有例外。
- `containerimage` 第一個 apply，然後人手動推第一版映像檔（K10），才 apply `application`。
- `pipeline` 最後 apply：它要讀 service、函式、bucket、distribution 的名稱。

### 8.2 三條 pipeline

| pipeline | stage | 說明 |
|---|---|---|
| `api` | Source → Build（`api-build`：建映像檔、推 ECR，輸出映像檔 URI）→ Approval（只有 sit）→ Deploy（`api-deploy`：§5.4 的三步） | 部署專案用 `#{BuildVariables.IMAGE_URI}` 拿映像檔 |
| `fn` | Source → Build（`fn-build`：建映像檔、推 ECR、`UpdateFunctionCode` 並發布版本，輸出 `VERSION`）→ Approval（只有 sit）→ Deploy（Lambda action，`PublishedTargetVersion = #{BuildVariables.VERSION}`，alias `live`，dev `AllAtOnce`、sit `Canary10Percent5Minutes`） | §2 第 2 點 |
| `web` | Source → Build（`web-build`：`npm ci`、`npm run build`）→ Approval（只有 sit）→ Deploy（S3 action，`Extract = true`）→ Invalidate（`web-invalidate`：`CreateInvalidation /*`） | S3 部署 action 不會清 CloudFront 快取，所以多一個小 CodeBuild 專案 |

- fn 的 Build 階段已經改了 `$LATEST` 並發布新版本，但 alias 還指著舊版，所以在 Deploy 之前流量不會切過去。sit 的 Approval 被拒絕時，新版本留著沒用到，下次執行會再發布一版。
- CodeBuild 在 Build 階段輸出變數，用 buildspec 的 `exported-variables`，REFERENCE 的範例 buildspec 要寫出來。

### 8.3 SSM 合約（樹 A）

| key | 寫 | 讀 |
|---|---|---|
| `containerimage/api_repository_url`、`fn_repository_url` | `containerimage` | `iam`、`application`、`pipeline` |
| `foundation/kms_key_arn`、`artifact_bucket_name`、`web_bucket_name`、`alert_topic_arn`、`connection_arn` | `foundation` | `iam`、`application`、`web`、`pipeline` |
| `network/vpc_id`、`app_subnet_ids` | `network` | `loadbalancer`、`application` |
| `iam/*_role_arn` | `iam` | `application`、`pipeline` |
| `loadbalancer/listener_arn`、`security_group_id` | `loadbalancer` | `application` |
| `application/cluster_name`、`api_service_name`、`api_task_family`、`fn_function_name`、`fn_alias_name` | `application` | `pipeline` |
| `web/distribution_id` | `web` | `pipeline` |

- `iam` 排在 `application` 之前：role 的權限範圍用命名規則組 ARN（service、函式、distribution），不讀後面的 stack。跟 v10 的 `iam` 一樣。
- key 的實際寫法照 example6 的命名。

### 8.4 dev／sit 的預設規格

| 項目 | dev | sit |
|---|---|---|
| 部署分支 | `develop` | `main` |
| manual approval | 不加 | 加（K6） |
| Lambda 部署策略 | `AllAtOnce` | `Canary10Percent5Minutes` |
| ECS 部署策略 | rolling | rolling |
| CodeBuild | `arm1.small` 類（K9） | 同左 |
| 建置 log 保存 | 30 天 | 90 天 |
| artifact 保存 | 30 天 | 30 天 |
| api service | 1 個 task | 2 個 task |

### 8.5 文件

`infra/README.md`（短）、`infra/REFERENCE.md`、`infra/architecture.drawio.svg`。REFERENCE 要寫：

- GitHub connection 的授權步驟。
- 第一次部署的順序（K10）。
- 三份範例 buildspec，含 `exported-variables`。
- 誰能執行 pipeline 要哪些 IAM action。
- 改用 blue/green 要做的事（`deployment`、`iam-role` 的 policy、ALB 多一個 target group）。
- destroy 之前的注意事項。

根 README 的範本表加一列，標準指南的範本清單加 example9。

## 9. 測試情境（TDD）

每個 module 用 `mock_provider "aws"`，至少要有：

| module | 正向 | 要被擋的 |
|---|---|---|
| `codeconnections-connection` | GitHub；GitLab 自架加 host | 自架沒給 host；GitHub 給了 host；名稱 33 字元 |
| `codebuild-project` | 建映像檔（privileged）；inline buildspec；三種變數類型 | `PLAINTEXT` 的 `DB_PASSWORD`；ARM 映像配 x86 compute；KMS 給 alias；timeout 4 分鐘 |
| `codepipeline` | source 加 build 加 deploy；有 approval；有變數；確認 `DetectChanges = "false"`、沒有 trigger | `stages` 放 `Source`；repository 格式錯；stage 名稱重複；未知 category |
| `ecs-service` 0.3.0 | 預設（跟 0.2.1 一樣）；`pipeline_managed`；`BLUE_GREEN` 建出 alternate target group 與 advanced configuration；`moved` 不重建 | `BLUE_GREEN` 沒有 role；`BLUE_GREEN` 但沒有 `pipeline_managed`；`BLUE_GREEN` 用外部 target group 接法 |
| `lambda-function` 0.2.0 | 預設（跟 0.1.1 一樣）；alias；`pipeline_managed` | `pipeline_managed` 沒有 alias；alias 名稱不合法 |
| `iam-role` 0.6.0 | 新的 policy 可以掛 | 白名單以外的 ECS policy |

範本 stack 的測試照 example6：每個 stack 的 `tests/` 驗 SSM 讀寫、名稱、跨 stack 一致的值，另外鎖住 §4 的控制（各 role 的 resource 範圍、`iam:PassRole` 條件、pipeline 沒有 trigger、sit 有 approval）。

## 10. 成本估計（美元，2026-10-29 查官方價目頁）

| 項目 | 價格 | 一個環境每月的量級 |
|---|---|---|
| CodePipeline V2 | 每分鐘 action 執行 0.002；每帳號每月 100 分鐘免費；manual approval 不計 | 三條 pipeline 各跑 20 次、每次約 10 分鐘：600 分鐘，扣掉免費約 1 |
| CodeBuild | ap-northeast-1 的 `arm1.small`（`ARM_CONTAINER` 配 `BUILD_GENERAL1_SMALL`）每分鐘 0.00425，`general1.small` 0.005；兩者合計每月 100 分鐘免費 | 每月 300 分鐘建置，約 1 |
| CodeConnections | 官方價目頁與 AWS price list 都沒有列費用（未確認是否完全免費） | 0 |
| artifact bucket | S3 標準儲存，30 天過期 | 低於 1 |
| CMK | 每把每月 1 | 1 |
| 應用程式本身（ECS、ALB、Lambda、CloudFront、NAT） | 照 example2、example6 | 最大宗；ALB 與 NAT 一個月就各十幾到幾十 |

- pipeline 本身每個環境每月不到 5 美元，大部分費用來自被部署的應用程式。
- api 的部署專案要等 service 穩定才結束（§5.4）。一次 rolling 部署約 5–10 分鐘，這段時間都算 CodeBuild 的分鐘數。

## 11. 風險與 mock 驗不到的事

- **connection 要手動授權**：apply 完是 `PENDING`，沒授權時 source stage 會失敗。REFERENCE 寫步驟。
- **`DetectChanges = "false"` 是否真的不觸發**：§2 第 7 點未確認。真實環境要確認 push 之後 pipeline 不會自己跑。
- **`pipeline_managed` 的 drift**：Terraform state 裡的 task definition 跟 service 實際用的不同，這是預期的；`terraform plan` 不會顯示差異，但看 state 的人會困惑。README 寫清楚。
- **Terraform 的設定變動要等下一次 pipeline 才部署**（§5.4）：改了環境變數之後要記得跑一次 api pipeline。
- **blue/green 的 target group 互換**：§5.4 未確認，範本不用 blue/green，所以只影響採用的專案。
- **CodeBuild 的權限等於 repo 寫入者的權限**（§4.1）：branch protection 沒開的話，任何能 push 的人都能用部署 role。
- **第一次部署**：映像檔不存在時 Lambda 建不起來，ECS 也拉不到映像檔（K10）。
- **destroy**：ECR 有映像檔時刪不掉（照 `ecr-repository` 的設定）；artifact bucket 與前端 bucket 有物件時刪不掉。REFERENCE〈destroy 之前〉要列。

## 12. Phase

| Phase | 內容 | 依賴 |
|---|---|---|
| L0 | 這份設計與實作流程 | — |
| L1 | `codeconnections-connection`、`codebuild-project` | L0 |
| L2 | `codepipeline` | L0 |
| L3 | `ecs-service` 0.3.0、`lambda-function` 0.2.0、`iam-role` 0.6.0 | L0 |
| L4 | 範本骨架、`containerimage`、`foundation`、`network`、`iam` | L1 發版 |
| L5 | `loadbalancer`、`application`、`web` | L3、L4 |
| L6 | `pipeline` | L1、L2、L5 |
| L7 | README、REFERENCE、架構圖；根 README（94 個 module）、標準指南；全量驗證；§10 價格查證；§14 | L6 |

- L1–L3 的目錄互不重疊，可以平行。
- L3 改的是已經有人在用的 module，`moved` 與預設值不變的測試要先寫。

## 13. 來源

- aws provider 6.70.0 schema：本機 `terraform providers schema -json`，§2 第 1 點、§5 的 resource、`aws_ecs_service.deployment_configuration` 的 `strategy`、`canary_configuration`、`linear_configuration`、`lifecycle_hook`。
- 既有 module：`modules/ecs-service`（只有 `ignore_changes = [desired_count]`）、`modules/lambda-function`（只收映像檔、沒有 alias）、`modules/iam-role/locals.tf`（managed policy 白名單）、`templates/example6`（`containerimage` 先 apply 的做法）。
- AWS 文件（2026-10-29 查）：
  - ECS 標準部署 action：<https://docs.aws.amazon.com/codepipeline/latest/userguide/action-reference-ECS.html>
  - Lambda 部署 action：<https://docs.aws.amazon.com/codepipeline/latest/userguide/action-reference-LambdaDeploy.html>、<https://docs.aws.amazon.com/codepipeline/latest/userguide/tutorials-lambda-deploy.html>
  - S3 部署 action：<https://docs.aws.amazon.com/codepipeline/latest/userguide/action-reference-S3Deploy.html>
  - ECS 原生 blue/green：<https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-blue-green.html>、<https://docs.aws.amazon.com/AmazonECS/latest/developerguide/blue-green-deployment-implementation.html>、<https://docs.aws.amazon.com/AmazonECS/latest/developerguide/alb-resources-for-blue-green.html>
  - 從 CodeDeploy 遷移到 ECS blue/green（2025-09-16）：<https://aws.amazon.com/blogs/containers/migrating-from-aws-codedeploy-to-amazon-ecs-for-blue-green-deployments>
  - 價格：<https://aws.amazon.com/codepipeline/pricing/>、<https://aws.amazon.com/codebuild/pricing/>、<https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/CodeBuild/current/ap-northeast-1/index.json>
- 實作時查證（2026-10-30）：
  - CodeConnections source action 與 pipeline role 的權限：<https://docs.aws.amazon.com/codepipeline/latest/userguide/action-reference-CodestarConnectionSource.html>、<https://docs.aws.amazon.com/codepipeline/latest/userguide/how-to-custom-role.html>
  - trigger：<https://docs.aws.amazon.com/codepipeline/latest/userguide/pipelines-triggers.html>
  - 執行模式：<https://docs.aws.amazon.com/codepipeline/latest/userguide/concepts-how-it-works.html>
  - CodeBuild compute 與映像：<https://docs.aws.amazon.com/codebuild/latest/userguide/build-env-ref-compute-types.html>、<https://docs.aws.amazon.com/codebuild/latest/userguide/ec2-compute-images.html>
  - ECS 管 ALB 的 policy：<https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonECSInfrastructureRolePolicyForLoadBalancers.html>

## 14. 實作後的變更

### 查證結果

- §2 第 7 點：`DetectChanges = "false"` 時 CodePipeline 不會因為新的 commit 啟動；triggers 文件的「No trigger – do not detect」也說明不會加 trigger、不會自動執行。push 之後到底會不會跑，仍要在真實帳號確認一次。
- `execution_mode` 的 `QUEUED` 只有 V2 能用，AWS 的預設是 `SUPERSEDED`；module 照設計預設 `QUEUED`。
- pipeline role 要同時有 `codeconnections:UseConnection` 與 `codestar-connections:UseConnection`。
- §5.6：`AmazonECSInfrastructureRolePolicyForLoadBalancers` 的 ARN 是 `arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers`，不在 `service-role/` 底下。
- §10：CodeBuild 的 ARM small 在 ap-northeast-1 是每分鐘 0.00425 美元；預設映像用 `aws/codebuild/amazonlinux-aarch64-standard:3.0`。

### module

- `codepipeline`：
  - 輸入 `source` 改名 `git_source`，因為 Terraform 在 module 區塊保留了 `source` 這個名稱。
  - source stage 的名稱固定：action `Source`、artifact `SourceArtifact`、namespace `SourceVariables`。
  - 多加的 validation：同一個 stage 的 action 名稱不重複、名稱格式、`run_order` 1–999。action 的 `timeout_in_minutes`、`region`、`role_arn` 不開放。
- `codebuild-project`：
  - `cache_modes` 預設改成不快取（設計是 Docker layer 加 source cache）。Docker layer cache 要搭配 privileged mode，加了 validation；source cache 對 `CODEPIPELINE` source 沒有作用。
  - 映像與 `type` 是否一致只檢查官方映像，因為 ARM 與 x86 共用同一組 `compute_type` 名稱。
  - `buildspec` 預設 `null`（用 repo 的 `buildspec.yml`），log group 預設 `/aws/codebuild/<name>`。
- `codeconnections-connection`：provider 不接受 `provider_type` 與 `host_arn` 同時給，所以給了 host 時 module 不送 `provider_type`。
- `ecs-service` 0.3.0：
  - listener rule 原本就有 `count`，預設版本保留原位址，blue/green 另外建 `blue_green`，不需要 `moved`。
  - blue/green 的 listener rule 轉到兩個 target group，權重 100／0，並忽略 `action`。這是 module 選的寫法，要在真實環境確認。
  - 多加的 validation：`bake_time_in_minutes` 與 `role_arn` 只能搭 `BLUE_GREEN`；bake time 0–1440；alternate target group 名稱 `<name>-<port>-alt` 不超過 32 字元。
  - 沒做 test listener rule、canary、linear，也沒有新增輸出。target group 互換仍未確認，沒有忽略 `load_balancer`。
- `lambda-function` 0.2.0：`publish` 預設傳 `null`，跟 0.1.1 完全一樣。`aws_lambda_permission` 沒有 qualifier，透過 alias ARN 呼叫時可能不涵蓋；example9 沒有呼叫端，不受影響。
- 既有測試只把位址從 `this` 改成 `this[0]`，斷言沒有改。

### 範本

- 前端 bucket 從 `foundation` 移到 `web`：`s3-bucket` 管整份 bucket policy，CloudFront 的讀取授權要寫 distribution，`foundation` 時還不存在。做法跟 example6 一樣，用 SSE-S3，名稱 `<name_prefix>-web-<account>`。
- ORDER 隨 Phase 增加；`network` 多發布 `vpc_cidr` 給內部 ALB 用。
- `iam`：
  - 註冊 task definition 限定 api 的 family；`Resource = "*"` 只用在 `ecr:GetAuthorizationToken`、`ecs:DescribeTaskDefinition`。
  - web-invalidate 用 distribution 的 tag 限定範圍（distribution ID 是隨機的）。
  - web-build 不能寫前端 bucket，由 pipeline 的 S3 部署 action 寫入；api-deploy 與 web-invalidate 只能讀 artifact。
  - fn 的部署沒有設 alarm，所以沒給 `cloudwatch:DescribeAlarms`。
- `loadbalancer`：內部 ALB 沒有 access log 與 WAF；dev 關刪除保護，sit 開。
- `application`：第一版映像的 tag 由 `api_bootstrap_image_tag`、`fn_bootstrap_image_tag` 決定，tfvars 是 `bootstrap`，不接受 `latest`。
- `web`：沒有 WAF、沒有 log、不讀 SSM。
- `ecs-service` 的部署策略從 rolling 改成 blue/green 時，service 與 listener rule 會換到另一個 resource 區塊，直接 apply 會刪掉重建 service。REFERENCE 附了 `moved` 的寫法，但沒有驗證過，採用前要在 dev 試一次。
- `iam` 用 `iam-role` `~> 0.5.0`；改用 blue/green 的專案要另外用 0.6.0 建 ECS 管 ALB 的 role。
- `pipeline`：
  - 建置專案是五個（§8.1 寫四個；多的 web-invalidate 跟 §8.2 一致）。只有 api-build、fn-build 開 privileged 與 Docker layer cache。
  - 人工核准由 tfvars 的 `approval_required` 控制；發布 `pipeline/{api,fn,web}_pipeline_name`。
  - 未確認：Lambda 部署 action 不給 input artifact、只靠 `PublishedTargetVersion` 能不能跑；api-deploy 用 `EnvironmentVariables` 覆寫 `IMAGE_URI` 的行為；失敗事件用 pipeline 名稱比對。
