# example9 參考資料

這份是 [`README.md`](./README.md) 的參考資料：README 只放第一次用範本需要的步驟，細節、合約、buildspec、runbook 與驗證紀錄都在這裡。

狀態：離線驗證通過，還沒在真實帳號 apply 過；第一次 apply 時逐項確認〈已知限制的細節〉與〈驗證〉的「雲端整合待驗證」。設計見 [`docs/design/v11/design-docs.md`](../../../docs/design/v11/design-docs.md) §3、§4、§8、§11，實作紀錄見 [`implement-process.md`](../../../docs/design/v11/implement-process.md)。設計與程式碼不一致時以程式碼為準，這份文件照程式碼寫。

## 成本

價格是 2026-10-29 查 AWS 官方價目頁的公開牌價，細節與來源見 [design §10](../../../docs/design/v11/design-docs.md)。

- CodePipeline V2：每分鐘 action 執行時間 0.002 美元，每個帳號每月前 100 分鐘免費；manual approval 不計費。
- CodeBuild：`arm1.small` 在 ap-northeast-1 每分鐘 0.00425 美元（`general1.small` 是 0.005），`general1.small` 或 `arm1.small` 每月前 100 分鐘免費。api 的部署專案要等 service 穩定才結束，一次 rolling 部署約 5–10 分鐘，這段時間都算建置分鐘數。
- CodeConnections：價目頁上找不到收費項目，沒有確認是否免費。
- 其他固定費用：CMK 約 1 美元／月，artifact bucket 的儲存很少（30 天過期）。
- 合起來 pipeline 本身每個環境每月不到 5 美元。大部分費用來自被部署的應用程式：NAT gateway、內部 ALB、api 的 Fargate task（dev 1 個、sit 2 個），量級照 example2。

不用的環境請照〈destroy〉拆掉。

## 檔案

`infra/terraform/` 底下每個 stack 一個目錄，另有 `stacks.sh`（依序跑各 stack）與 `check-ssm-contract.sh`（靜態檢查 SSM 合約與 tfvars 一致性）。每個 stack 的固定檔案跟 example6 相同（`versions.tf`、`providers.tf`、`common.tf`、`ssm-outputs.tf`、`envs/<env>.tfvars`、`envs/<env>.tfbackend`、`tests/`、`.terraform.lock.hcl`；有讀上游的 stack 另有 `ssm-inputs.tf`），`common.tf` 8 個 stack 一字不差。只有 aws provider，沒有 provider alias。buildspec 不在這個 repo：它們放在應用程式 repo，範本只指定路徑（design K5），範例見〈範例 buildspec〉。

## stack 的內容與依賴

apply 順序與 `ORDER` 見 README。下游只讀上游發布的 key。`<prefix>` 是 `<project>-<env>`（範本是 `cicd-dev`、`cicd-sit`），`<account>` 是 `expected_account_id`。

| 順序 | stack | 建的東西 | 讀 |
|---|---|---|---|
| 1 | `containerimage` | ECR repository `<prefix>-api`、`<prefix>-fn`：tag 不可覆寫（`IMMUTABLE`）、加密用 AES256（這時共用 CMK 還不存在）、未加 tag 的映像 7 天刪除、最多留 50 個 | 無 |
| 2 | `foundation` | 共用 CMK `<prefix>`（key policy 放行本 region 的 CloudWatch Logs、CloudWatch、SNS、EventBridge）；artifact bucket `<prefix>-artifacts-<account>`（CMK、30 天過期）；告警 topic `<prefix>-alerts`（CMK、email 訂閱、放行 `events.amazonaws.com` 發布）；GitHub connection `<prefix>-github`（建好時是 `PENDING`） | 無 |
| 3 | `network` | VPC `<prefix>`（`10.30.0.0/16`、2 個 AZ）：public subnet（`/24`）只放 NAT，app subnet（`/20`）放 ECS task 與內部 ALB；NAT 預設 `single`；S3 gateway endpoint | 無 |
| 4 | `iam` | 9 個 role，下一段的表；每個只信任一個服務，帶 `aws:SourceAccount`，CodeBuild 的 role 另外限定專案 ARN，pipeline role 限定 `<prefix>-*` 的 pipeline | containerimage、foundation |
| 5 | `loadbalancer` | 內部 ALB `<prefix>-alb`：HTTP 80 listener，security group 只收 VPC CIDR 的 80、只往 VPC CIDR 的 `app_port`（8080）連線；deletion protection dev 關、sit 開；`HTTPCode_ELB_5XX_Count` 告警送告警 topic | foundation、network |
| 6 | `application` | ECS cluster `<prefix>`（Container Insights `enhanced`）；api service `<prefix>-api`：Fargate ARM64、256 CPU、512 MiB、port 8080、task 數 dev 1／sit 2、`pipeline_managed`、rolling（最少 100%、最多 200%、circuit breaker），掛在 ALB listener 的 rule（priority 100、`/*`、health check `/health`），security group 只收 ALB 的 8080、對外只開 HTTPS；fn 函式 `<prefix>-fn`：arm64、512 MB、30 秒、alias `live`、`pipeline_managed`。log group `/ecs/<prefix>-api`、`/aws/lambda/<prefix>-fn` 用 CMK，保存 dev 30 天、sit 90 天 | containerimage、foundation、network、iam、loadbalancer |
| 7 | `web` | 前端 bucket `<prefix>-web-<account>`（SSE-S3、不過期、只讓這個 distribution 經 OAC 讀）；CloudFront `<prefix>-web`（預設網域、`PriceClass_200`、`index.html`、SPA fallback），沒有 WAF 與 log | 無 |
| 8 | `pipeline` | 5 個 CodeBuild 專案、3 條 pipeline（〈三條 pipeline〉）；EventBridge rule `<prefix>-pipeline-failed`：三條 pipeline 的執行變成 `FAILED` 時送告警 topic | containerimage、foundation、iam、application、web |

`iam` 的 role（`policies.tf`）：

| role | 信任 | 權限 |
|---|---|---|
| `<prefix>-api-execution` | `ecs-tasks` | 從 api repository 拉映像、寫 `/ecs/<prefix>-api` 的 log |
| `<prefix>-api-task` | `ecs-tasks` | 沒有權限；api 要呼叫 AWS 服務時再加 |
| `<prefix>-fn-lambda` | `lambda` | 寫 `/aws/lambda/<prefix>-fn` 的 log。沒有 ECR 權限：Lambda 用執行 apply 的身分拉映像 |
| `<prefix>-api-build-codebuild` | `codebuild`，限 `api-build` 專案 | 推到 api repository |
| `<prefix>-api-deploy-codebuild` | `codebuild`，限 `api-deploy` 專案 | `DescribeTaskDefinition`；只對 api family 的 `RegisterTaskDefinition`（`TagResource` 只能跟著註冊）；只對 api service 的 `UpdateService`（條件是 task definition 屬於 api family）與 `DescribeServices`；只對 api 的兩個 role 的 `iam:PassRole`（條件 `iam:PassedToService = ecs-tasks.amazonaws.com`） |
| `<prefix>-fn-build-codebuild` | `codebuild`，限 `fn-build` 專案 | 推到 fn repository；只對 fn 函式的 `GetFunction`、`UpdateFunctionCode`、`PublishVersion` |
| `<prefix>-web-build-codebuild` | `codebuild`，限 `web-build` 專案 | 只有共同的部分，不能寫前端 bucket（寫 bucket 的是 pipeline 的 S3 部署 action） |
| `<prefix>-web-invalidate-codebuild` | `codebuild`，限 `web-invalidate` 專案 | `CreateInvalidation`、`GetInvalidation`，只對帶有 `Project`、`Environment`、`Managed`、`Stack = web` 這組 tag 的 distribution |
| `<prefix>-pipeline` | `codepipeline`，限 `<prefix>-*` | artifact bucket 與 CMK；只對這一個 connection 的 `codeconnections:UseConnection` 與 `codestar-connections:UseConnection`；只對 5 個專案的 `StartBuild`、`BatchGetBuilds`；Lambda 部署 action 對 fn 函式與它的版本、alias 的動作與 `/<region>/codepipeline/<prefix>-fn` 的 log；S3 部署 action 對前端 bucket 的寫入 |

5 個建置 role 共同的部分：寫自己的 `/aws/codebuild/<專案名稱>` log、讀 artifact bucket、用 CMK 解密。會產出 artifact 的 `api-build`、`fn-build`、`web-build` 另外可以寫 artifact 與加密；`api-deploy`、`web-invalidate` 只能讀。建置 role 都不能讀 Secrets Manager，也不放進 VPC（design §4.1）。`Resource "*"` 只用在沒有 resource type 的 `ecr:GetAuthorizationToken` 與 `ecs:DescribeTaskDefinition`。

「讀」欄看不出來的順序限制：

- `iam` 比 `application`、`web`、`pipeline` 先 apply，拿不到它們的 ARN，所以照命名規則組（`iam/naming.tf`）：cluster `<prefix>`、service 與 task family `<prefix>-api`、函式 `<prefix>-fn`、前端 bucket `<prefix>-web-<account>`、建置專案 `<prefix>-<專案>`、pipeline `<prefix>-api`、`-fn`、`-web`。distribution ID 是隨機的，所以改用 `web` 的 provider 自動加上的 tag 限定。改任何一個名稱時，`iam` 要一起改；兩邊的測試各自寫死同一個期望值。
- `iam` 的 role 等 policy 附加完才發布，`application`、`pipeline` 看到 role 時權限已經在。
- `application` 要等兩個 repository 裡都有 `bootstrap` 映像才 apply 得過（design K10）。
- `pipeline` 最後 apply：它要讀 service、函式、bucket、distribution 的名稱。
- `app_port` 在 `loadbalancer` 與 `application` 各一份，tfvars 的測試確認兩邊一致。

## 三條 pipeline

每個元件一條 pipeline（design K4），都指向同一個 repo 與分支，只差在用哪份 buildspec。pipeline 都是 V2、`QUEUED` 模式；Source stage 由 `codepipeline` module 產生，固定 `DetectChanges = "false"`、不建 trigger，所以只會在有人按執行時跑（design D7）。Build action 的 `exported-variables` 放在 namespace `BuildVariables`。

| pipeline | stage |
|---|---|
| `<prefix>-api` | Source → Build（`api-build`：建映像檔、推 ECR，輸出 `IMAGE_URI`）→ Approval（只有 sit）→ Deploy（`api-deploy`：用 `#{BuildVariables.IMAGE_URI}` 註冊新的 task definition 版本、更新 service、等到穩定） |
| `<prefix>-fn` | Source → Build（`fn-build`：建映像檔、推 ECR、更新函式並發布版本，輸出 `VERSION`）→ Approval（只有 sit）→ Deploy（Lambda 部署 action：把 alias `live` 切到 `#{BuildVariables.VERSION}`，沒有 input artifact） |
| `<prefix>-web` | Source → Build（`web-build`：`npm ci`、`npm run build`，輸出 `BuildArtifact`）→ Approval（只有 sit）→ Deploy（S3 部署 action，`Extract = true`，寫進前端 bucket）→ Invalidate（`web-invalidate`：清 CloudFront 快取） |

dev 與 sit 的差別（`pipeline/envs/*.tfvars`）：

| 項目 | dev | sit |
|---|---|---|
| 部署的分支（`branch`） | `develop` | `main` |
| manual approval（`approval_required`） | 不加 | 加 |
| fn 切換 alias 的方式（`fn_deploy_strategy`） | `AllAtOnce` | `Canary10Percent5Minutes` |
| 建置 log 保存（`log_retention_days`） | 30 天 | 90 天 |

5 個建置專案都是 `BUILD_GENERAL1_SMALL`、`ARM_CONTAINER`、`aws/codebuild/amazonlinux-aarch64-standard:3.0`，單次 30 分鐘逾時，同一個專案同時只跑一個建置。要跑 `docker build` 的 `api-build`、`fn-build` 開 `privileged_mode` 與 Docker layer cache。環境變數都是 `PLAINTEXT`，只放名稱與 URL；`codebuild-project` 會擋名稱像 secret 的 `PLAINTEXT` 變數。建置需要 secret 時改用 `SECRETS_MANAGER` 類型，並在 `iam` 明確給那一個 secret。

fn 的 Build stage 已經改了 `$LATEST` 並發布新版本，但 alias 還指著舊版，所以 Deploy 之前流量不會切過去。sit 的 Approval 被拒絕時，新版本留著沒人用，下次執行會再發布一版。

## SSM 合約

路徑 `/<project>/<env>/<stack>/<key>`（[ADR-0003](../../../docs/adr/0003-cross-stack-values-via-ssm-only.md)），只有樹 A，沒有 bridge。下表照各 stack 的 `ssm-outputs.tf` 與 `ssm-inputs.tf` 整理，不一致時以程式碼為準。

| key | 型別 | 內容 | 讀的 stack |
|---|---|---|---|
| `containerimage/api_repository_url` | String | api 的 ECR repository URL，不含 tag | `iam`、`application`、`pipeline` |
| `containerimage/fn_repository_url` | String | fn 的 ECR repository URL，不含 tag | `iam`、`application`、`pipeline` |
| `foundation/kms_key_arn` | String | 共用 CMK | `iam`、`application`、`pipeline` |
| `foundation/artifact_bucket_name` | String | artifact bucket | `iam`、`pipeline` |
| `foundation/alert_topic_arn` | String | 告警 topic | `loadbalancer`、`pipeline` |
| `foundation/connection_arn` | String | GitHub connection | `iam`、`pipeline` |
| `network/vpc_id` | String | VPC ID | `loadbalancer`、`application` |
| `network/vpc_cidr` | String | VPC CIDR | `loadbalancer` |
| `network/app_subnet_ids` | StringList | app subnet | `loadbalancer`、`application` |
| `iam/api_execution_role_arn`、`api_task_role_arn`、`fn_role_arn` | String | api 的 execution 與 task role、fn 的 role | `application` |
| `iam/api_build_role_arn`、`api_deploy_role_arn`、`fn_build_role_arn`、`web_build_role_arn`、`web_invalidate_role_arn` | String | 5 個建置專案的 role | `pipeline` |
| `iam/pipeline_role_arn` | String | 三條 pipeline 共用的 role | `pipeline` |
| `loadbalancer/listener_arn` | String | ALB 的 HTTP listener | `application` |
| `loadbalancer/security_group_id` | String | ALB 的 security group | `application` |
| `application/cluster_name` | String | ECS cluster 名稱 | `pipeline` |
| `application/api_service_name` | String | api service 名稱 | `pipeline` |
| `application/api_task_family` | String | api 的 task definition family | `pipeline` |
| `application/fn_function_name` | String | fn 函式名稱 | `pipeline` |
| `application/fn_alias_name` | String | fn 的 alias（`live`） | `pipeline` |
| `web/web_bucket_name` | String | 前端 bucket | `pipeline` |
| `web/distribution_id` | String | CloudFront distribution ID | `pipeline` |
| `pipeline/api_pipeline_name`、`fn_pipeline_name`、`web_pipeline_name` | String | 三條 pipeline 的名稱 | 沒有 stack 讀；給執行 pipeline 的人或之後的自動化 |

跟 design §8.3 的差異：前端 bucket 由 `web` 建、由 `web` 發布 `web/web_bucket_name`（design 放在 `foundation`），因為 bucket policy 要寫明 distribution，而 `foundation` apply 時 distribution 還不存在；`network` 多發布 `vpc_cidr` 給 ALB 的 security group；`loadbalancer` 讀告警 topic 給 ALB 的告警；`web` 不讀任何 key；多了 `pipeline` 的三個 key。

`check-ssm-contract.sh` 檢查兩件事：每個讀取的 key 都由 `ORDER` 更早的 stack 發布、型別一致；同一個 env 各 stack tfvars 的 `project`、`env`、`aws_region`、`expected_account_id` 一致，`env` 等於檔名。

## 第一次 apply

複製範本的專案第一次在自己帳號部署時照這個順序（以 `dev` 為例，在 `infra/terraform` 底下，AWS 身分自己帶）。這個 repo 只做離線驗證，不 apply。

1. 先建 repository 與 connection：

   ```bash
   ./stacks.sh dev containerimage apply
   ./stacks.sh dev foundation apply
   ```

2. 授權 GitHub connection（〈GitHub connection 的授權〉）。這一步只要在第一次執行 pipeline 之前做完就好，先做可以早點發現 GitHub 那邊的權限問題。
3. 手動 build api 與 fn 的第一版映像檔（arm64），tag 用 `bootstrap`（`application` tfvars 的 `api_bootstrap_image_tag`、`fn_bootstrap_image_tag`）。repository 的 tag 不可覆寫，所以每個 repository 只能推一次 `bootstrap`：

   ```bash
   api_repo=$(aws ssm get-parameter --name /cicd/dev/containerimage/api_repository_url --query Parameter.Value --output text)
   fn_repo=$(aws ssm get-parameter --name /cicd/dev/containerimage/fn_repository_url --query Parameter.Value --output text)
   aws ecr get-login-password | docker login --username AWS --password-stdin "${api_repo%%/*}"
   docker build --platform linux/arm64 -t "$api_repo:bootstrap" <api 目錄>
   docker push "$api_repo:bootstrap"
   docker build --platform linux/arm64 -t "$fn_repo:bootstrap" <fn 目錄>
   docker push "$fn_repo:bootstrap"
   ```

   api 的映像要在 8080 port 回應 `GET /health`，不然 ALB 的 health check 不會過，ECS 會一直重開 task。fn 的映像要能在 Lambda 上執行（用 AWS 的 Lambda base image，或裝 runtime interface client）。bootstrap 可以是應用程式目前的版本，也可以是只回 health check 的最小映像；之後的版本都由 pipeline 部署。
4. 跑全部：

   ```bash
   ./stacks.sh dev all apply
   ```

   已經 apply 過的兩個 stack 不會有變更。ECS service 建立時不等 task 穩定（`wait_for_steady_state = false`），apply 完要自己到 console 確認 task 跑起來、target group 是 healthy。CloudFront 建立要幾分鐘到十幾分鐘。
5. 在應用程式 repo 的 `buildspec/` 放好 5 份 buildspec（〈範例 buildspec〉），並替 `develop`（dev）、`main`（sit）開 branch protection（〈branch protection〉）。
6. 手動執行三條 pipeline（〈執行 pipeline〉）：

   ```bash
   aws codepipeline start-pipeline-execution --name cicd-dev-api
   aws codepipeline start-pipeline-execution --name cicd-dev-fn
   aws codepipeline start-pipeline-execution --name cicd-dev-web
   ```

   前端 bucket 在 web pipeline 跑完之前是空的，CloudFront 網址（`./stacks.sh dev web output` 的 `web_url`）會回 403。
7. 告警 topic 的每位 email 收件人會收到 SNS 的確認信，要點確認才收得到 pipeline 失敗與 ALB 的告警。

sit 照同樣的順序在 sit 的帳號再做一次，connection 也要再授權一次。

## GitHub connection 的授權

`foundation` 建的 connection 狀態是 `PENDING`，要有人在 AWS console 按一次授權（安裝 GitHub App）才會變成 `AVAILABLE`。Terraform 做不到這一步。沒授權之前，pipeline 照樣建得起來，但 Source stage 一執行就失敗。

做這一步的人要同時有兩邊的權限：AWS 這邊能更新這個 connection，GitHub 這邊能替 repo 所在的 organization 安裝 GitHub App（organization owner，或被允許安裝 app 的人）。

1. 用 `dev` 帳號登入 AWS console，region 選 `ap-northeast-1`，打開 CodePipeline 的 Settings → Connections。
2. 選 `cicd-dev-github`（狀態 Pending），按 Update pending connection。
3. 在跳出的 GitHub 視窗選 Install a new app（organization 已經裝過 AWS Connector for GitHub 時，直接選既有的 installation）。安裝範圍選 Only select repositories，只勾應用程式 repo（範本是 `example-org/example-app`）。不要選 All repositories：connection 能讀的 repo 就是這個 app 能讀的 repo。
4. 回到 console 按 Connect，狀態變成 Available。

確認：

```bash
arn=$(aws ssm get-parameter --name /cicd/dev/foundation/connection_arn --query Parameter.Value --output text)
aws codeconnections get-connection --connection-arn "$arn" --query Connection.ConnectionStatus --output text   # AVAILABLE
```

`./stacks.sh dev foundation output` 的 `connection_status` 也看得到狀態，但那是上次 apply 時的值。

- connection 被刪掉重建（例如 destroy 後再 apply `foundation`）時，新的 connection 又是 `PENDING`，要再授權一次。ARN 也會變，`iam` 與 `pipeline` 要重新 apply。
- 在 GitHub 移除 app 或把 repo 移出安裝範圍，Source stage 會失敗，connection 狀態不一定會跟著變。

## 範例 buildspec

5 份 buildspec 放在應用程式 repo 的 `buildspec/` 底下，檔名就是 `pipeline/builds.tf` 指定的路徑。buildspec 跟著程式碼改，調整建置不需要 apply Terraform（design K5）。下面的範例只示範範本要的合約：哪些環境變數由 Terraform 給、哪些變數要用 `exported-variables` 輸出給下一個 stage。路徑、Dockerfile 位置都是佔位，照自己的 repo 改。這些範例沒有在真實的 CodeBuild 跑過。

| 檔案 | Terraform 給的環境變數 | 輸出 |
|---|---|---|
| `buildspec/api-build.yml` | `REPOSITORY_URI` | `IMAGE_URI` |
| `buildspec/api-deploy.yml` | `CLUSTER_NAME`、`SERVICE_NAME`、`TASK_FAMILY`、`CONTAINER_NAME`（`app`）；`IMAGE_URI` 由 pipeline 的 action 帶入 | 無 |
| `buildspec/fn-build.yml` | `REPOSITORY_URI`、`FUNCTION_NAME` | `VERSION` |
| `buildspec/web-build.yml` | 無 | artifact（`dist` 底下的所有檔案） |
| `buildspec/web-invalidate.yml` | `DISTRIBUTION_ID` | 無 |

幾個共同的地方：

- CodeBuild 跑在 ARM 上，`docker build` 出來的就是 arm64 映像，跟 ECS 與 Lambda 的架構一致；`--platform linux/arm64` 只是寫明。
- repository 的 tag 不可覆寫，同一個 commit 重跑時要用不同的 tag。範例用 commit 前 12 碼加 CodeBuild 的建置編號。pipeline 從 CodeConnections 拿 source 時，`CODEBUILD_RESOLVED_SOURCE_VERSION` 是 commit ID（CodeBuild 文件；沒有在真實帳號確認）。
- `exported-variables` 輸出的是建置結束時環境變數的值，所以要在同一個 shell 裡設定。範例用 `shell: bash`，同一份 buildspec 的指令共用一個 shell，變數會留到後面的指令。
- 不要把要部署的動作放在 `post_build`：`build` 失敗時 `post_build` 照樣會跑。

`buildspec/api-build.yml`：

```yaml
version: 0.2

env:
  shell: bash
  exported-variables:
    - IMAGE_URI

phases:
  build:
    commands:
      - aws ecr get-login-password | docker login --username AWS --password-stdin "${REPOSITORY_URI%%/*}"
      - IMAGE_TAG="${CODEBUILD_RESOLVED_SOURCE_VERSION:0:12}-${CODEBUILD_BUILD_NUMBER}"
      - docker build --platform linux/arm64 -t "$REPOSITORY_URI:$IMAGE_TAG" <api 目錄>
      - docker push "$REPOSITORY_URI:$IMAGE_TAG"
      - export IMAGE_URI="$REPOSITORY_URI:$IMAGE_TAG"
```

`buildspec/api-deploy.yml`（design §5.4）：拿 family 最新的版本（Terraform 最後註冊的那一版，環境變數、secret、CPU 的變動都在裡面），只換掉 `app` container 的映像，註冊成新版本，再 `UpdateService` 並等到穩定。`describe-task-definition` 的輸出有些欄位 `register-task-definition` 不收，所以只挑註冊需要的欄位：

```yaml
version: 0.2

env:
  shell: bash

phases:
  build:
    commands:
      - |
        set -euo pipefail
        aws ecs describe-task-definition --task-definition "$TASK_FAMILY" --include TAGS > current.json
        jq --arg name "$CONTAINER_NAME" --arg image "$IMAGE_URI" '
          .tags as $tags
          | .taskDefinition
          | .containerDefinitions |= map(if .name == $name then .image = $image else . end)
          | {family, taskRoleArn, executionRoleArn, networkMode, containerDefinitions, volumes,
             placementConstraints, requiresCompatibilities, cpu, memory, runtimePlatform,
             ephemeralStorage, proxyConfiguration, pidMode, ipcMode}
          | with_entries(select(.value != null))
          | if ($tags | length) > 0 then .tags = $tags else . end
        ' current.json > next.json
        revision=$(aws ecs register-task-definition --cli-input-json file://next.json \
          --query taskDefinition.taskDefinitionArn --output text)
        aws ecs update-service --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" \
          --task-definition "$revision" > /dev/null
        aws ecs wait services-stable --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME"
```

- `aws ecs wait services-stable` 最多等 10 分鐘（每 15 秒查一次、40 次），等不到就讓建置失敗，pipeline 也跟著失敗並送告警。rolling 部署失敗時 circuit breaker 會自動回到上一版。
- 部署專案的 role 只能註冊 api family 的版本、只能讓 api service 改用 api family 的版本；`iam:PassRole` 只給 api 的 execution role 與 task role。新版本照抄舊版本的 role，所以 buildspec 不能換 role。
- 範例用 `jq` 改 JSON；CodeBuild 的標準映像有沒有內建 `jq` 沒有確認，沒有的話在 `install` phase 先裝。

`buildspec/fn-build.yml`：建映像檔、推 ECR、讓函式的 `$LATEST` 改用新映像、等更新完成，再發布一個版本。alias 由下一個 stage 的 Lambda 部署 action 切換：

```yaml
version: 0.2

env:
  shell: bash
  exported-variables:
    - VERSION

phases:
  build:
    commands:
      - aws ecr get-login-password | docker login --username AWS --password-stdin "${REPOSITORY_URI%%/*}"
      - IMAGE_TAG="${CODEBUILD_RESOLVED_SOURCE_VERSION:0:12}-${CODEBUILD_BUILD_NUMBER}"
      - docker build --platform linux/arm64 -t "$REPOSITORY_URI:$IMAGE_TAG" <fn 目錄>
      - docker push "$REPOSITORY_URI:$IMAGE_TAG"
      - aws lambda update-function-code --function-name "$FUNCTION_NAME" --image-uri "$REPOSITORY_URI:$IMAGE_TAG" > /dev/null
      - aws lambda wait function-updated-v2 --function-name "$FUNCTION_NAME"
      - export VERSION="$(aws lambda publish-version --function-name "$FUNCTION_NAME" --query Version --output text)"
```

`buildspec/web-build.yml`：輸出的 artifact 由 S3 部署 action 解開放進前端 bucket，`dist` 底下的結構就是 bucket 裡的結構：

```yaml
version: 0.2

phases:
  build:
    commands:
      - npm ci
      - npm run build

artifacts:
  base-directory: dist
  files:
    - '**/*'
```

需要特定的 Node.js 版本時，在 `install` phase 加 `runtime-versions`；前端不在 repo 根目錄時，先 `cd` 進去，`base-directory` 也跟著改。

`buildspec/web-invalidate.yml`：S3 部署 action 不會清 CloudFront 的快取，所以 Deploy 之後多跑這一步。等 invalidation 完成再結束，pipeline 顯示成功時新版本已經生效：

```yaml
version: 0.2

env:
  shell: bash

phases:
  build:
    commands:
      - id=$(aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths '/*' --query Invalidation.Id --output text)
      - aws cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$id"
```

S3 部署 action 只上傳、不刪除，舊版本留下的檔案會一直在 bucket 裡。build 結果的檔名有 hash 時通常不影響；要清掉就自己在 `web-build` 之外處理（`web-build` 的 role 不能寫 bucket）。

## 執行 pipeline

pipeline 不會自動跑（design D7）：Source action 的 `DetectChanges` 是 `false`，也沒有 trigger，push 到分支不會觸發。要部署就手動執行，每次都拿分支當下最新的 commit：

```bash
aws codepipeline start-pipeline-execution --name cicd-sit-api
aws codepipeline get-pipeline-state --name cicd-sit-api   # 看每個 stage 的狀態
```

也可以在 console 的 pipeline 頁面按 Release change。三條 pipeline 互相獨立，可以只部署其中一個元件。

sit 的 pipeline 停在 Approval 時，核准的人在 console 按 Review，或用 CLI。token 從 `get-pipeline-state` 的 Approval stage 取得：

```bash
aws codepipeline get-pipeline-state --name cicd-sit-api \
  --query "stageStates[?stageName=='Approval'].actionStates[0].latestExecution.token" --output text
aws codepipeline put-approval-result --pipeline-name cicd-sit-api --stage-name Approval --action-name Approve \
  --result summary="確認部署",status=Approved --token <token>
```

Approval 沒有人處理時，7 天後會自動失敗（CodePipeline 的預設）。

pipeline 是 `QUEUED` 模式：前一次還在跑時再按執行，新的那次會排隊，不會中斷前一次。

### 誰能執行、誰能核准

範本不建給人用的權限（design §4）。執行與核准是兩件事，可以給不同的人。下面是 sit 帳號的例子，dev 把 `222222222222`、`cicd-sit` 換成 `111111111111`、`cicd-dev`。

執行與查看：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "StartAndWatch",
      "Effect": "Allow",
      "Action": [
        "codepipeline:StartPipelineExecution",
        "codepipeline:StopPipelineExecution",
        "codepipeline:RetryStageExecution",
        "codepipeline:GetPipeline",
        "codepipeline:GetPipelineState",
        "codepipeline:GetPipelineExecution",
        "codepipeline:ListPipelineExecutions",
        "codepipeline:ListActionExecutions"
      ],
      "Resource": "arn:aws:codepipeline:ap-northeast-1:222222222222:cicd-sit-*"
    },
    {
      "Sid": "ListInConsole",
      "Effect": "Allow",
      "Action": ["codepipeline:ListPipelines"],
      "Resource": "*"
    },
    {
      "Sid": "ReadBuildLogs",
      "Effect": "Allow",
      "Action": ["codebuild:BatchGetBuilds", "logs:GetLogEvents"],
      "Resource": [
        "arn:aws:codebuild:ap-northeast-1:222222222222:project/cicd-sit-*",
        "arn:aws:logs:ap-northeast-1:222222222222:log-group:/aws/codebuild/cicd-sit-*:*"
      ]
    }
  ]
}
```

核准（只有 sit 有 Approval stage），resource 是 `<pipeline>/<stage>/<action>`；核准的人也需要上面的 `GetPipelineState` 才拿得到 token：

```json
{
  "Sid": "ApproveSitDeploys",
  "Effect": "Allow",
  "Action": ["codepipeline:PutApprovalResult"],
  "Resource": "arn:aws:codepipeline:ap-northeast-1:222222222222:cicd-sit-*/Approval/Approve"
}
```

- `StartPipelineExecution` 就是部署權限：它會用 pipeline role 與建置 role 的權限把分支上的程式碼推到環境裡。只給負責部署的人。
- `StopPipelineExecution`、`RetryStageExecution` 視需要給，不需要可以拿掉。
- V2 的 `StartPipelineExecution` 可以指定 commit（`--source-revisions`）。指定的 commit 是不是一定要在設定的分支上，沒有在真實帳號確認；確認之前，當成拿到這個權限的人可以部署 repo 裡任何 commit。
- 動作清單依 CodePipeline 的 IAM 文件整理，沒有對真實帳號核對。

## branch protection

建置專案執行的是應用程式 repo 裡的 buildspec（design §4.1），所以能改部署分支的人，等於能用建置 role 的權限做事。例如能 push 到 `main` 的人，可以改 `buildspec/api-deploy.yml`，讓它用部署 role 註冊任何映像的 task definition。範本把每個 role 的權限限定在自己的元件，但這條信任鏈的起點在 GitHub。所以：

- 在 GitHub 替部署的分支（dev 的 `develop`、sit 的 `main`）開 branch protection 或 ruleset：只能透過 PR 合併、至少一位 reviewer 核准、不允許 force push 與刪除分支，管理員也一樣適用。
- `buildspec/` 目錄可以用 CODEOWNERS 指定平台團隊 review。
- GitHub App 只裝在應用程式 repo（〈GitHub connection 的授權〉）。
- 換 `pipeline` tfvars 的 `branch` 時，新的分支也要有同樣的保護。

## Terraform 的設定變動什麼時候生效

api service 與 fn 函式都是 `pipeline_managed`（design D6、§5.4）。Terraform 只用 `bootstrap` 映像建出第一版，之後忽略版本的變動：

- api：service 忽略 `task_definition`。改 `application` 的 CPU、記憶體或 container 設定再 apply 時，Terraform 會在 family 註冊一個新版本，但 service 不會改用它。下一次執行 api pipeline 時，`api-deploy` 拿 family 最新的版本、換上新映像再部署，Terraform 的變動才會生效。**改完 api 或 fn 的設定，要記得跑一次對應的 pipeline。**
- Terraform 註冊的新版本裡映像還是 `bootstrap`。不要在 console 讓 service 直接改用最新的版本，那會把映像換回 bootstrap；一律透過 pipeline 部署。
- fn：函式忽略 `image_uri`，alias 忽略指向的版本與流量設定。改 `fn_memory_size`、`fn_timeout` 這類設定時，Terraform 改的是 `$LATEST` 並發布一個新版本，但 alias `live` 還指著舊版本，而已發布的版本設定不能改。所以 fn 的設定也要等下一次執行 fn pipeline，`fn-build` 從 `$LATEST` 發布新版本、alias 切過去之後才生效。
- 改 `api_bootstrap_image_tag`、`fn_bootstrap_image_tag` 不會換掉執行中的版本。

### state 跟實際的差異

這是預期的 drift，`terraform plan` 不會顯示：

| 資源 | Terraform state 裡 | 實際 |
|---|---|---|
| api service 的 task definition | Terraform 最後註冊的版本（映像 `bootstrap`） | pipeline 最後註冊的版本 |
| fn 函式的映像 | `<repository>:bootstrap` | pipeline 最後推的映像 |
| fn alias `live` 指的版本 | 第一次 apply 發布的版本 | pipeline 最後切過去的版本 |

要知道環境裡跑的是哪一版，看 AWS，不要看 state：

```bash
aws ecs describe-services --cluster cicd-dev --services cicd-dev-api --query 'services[0].taskDefinition'
aws lambda get-alias --function-name cicd-dev-fn --name live --query FunctionVersion
```

### 回滾

- api：rolling 部署失敗時 circuit breaker 自動回到上一版。要回到更早的版本，就讓 service 改用那個版本的 task definition（`aws ecs update-service --task-definition <family>:<revision>`）；舊版本裡是當時的設定與映像。
- fn：把 alias 指回舊版本（`aws lambda update-alias --function-name cicd-dev-fn --name live --function-version <version>`）。
- web：從舊的 commit 重新執行 web pipeline（〈誰能執行、誰能核准〉提到的 `--source-revisions`），或 revert 之後再執行。
- 手動回滾之後，下一次執行 pipeline 會照分支最新的 commit 再部署一次。

## 改用 blue/green

範本的 api 用 rolling（design D8）。`ecs-service` 0.3.0 支援 ECS 原生的 blue/green，不需要 CodeDeploy。module 的做法與限制見 `ecs-service` README 的〈原生 blue/green〉。改的時候要動 `iam` 與 `application` 兩個 stack，`api-deploy` 的 buildspec 不用改：`UpdateService` 會照 service 的部署策略走。

1. `iam`：多建一個讓 ECS 改 ALB listener rule 的 role，掛 AWS managed policy `AmazonECSInfrastructureRolePolicyForLoadBalancers`。這個 policy 從 `iam-role` 0.6.0 起才在白名單內，範本的 `module "role"` 用的是 `~> 0.5.0`，所以這個 role 另外寫一個 module block：

   ```hcl
   # iam/roles.tf
   module "api_ecs_infrastructure_role" {
     source  = "app.terraform.io/libterty/iam-role/aws"
     version = "~> 0.6.0"

     name                = "${local.name_prefix}-api-ecs-infrastructure"
     trust               = { service_principals = ["ecs.amazonaws.com"] }
     managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"]
   }
   ```

   並在 `iam/ssm-outputs.tf` 的 `published_strings` 加 `api_infrastructure_role_arn = module.api_ecs_infrastructure_role.arn`。trust 沒有加 `source_account`：ECS assume 這個 role 時會不會帶 `aws:SourceAccount`，沒有確認。
2. `application`：`ssm-inputs.tf` 加 `api_infrastructure_role_arn = "iam/api_infrastructure_role_arn"`，`api.tf` 的 `deployment` 改成：

   ```hcl
       deployment = {
         strategy             = "BLUE_GREEN"
         bake_time_in_minutes = 5
         role_arn             = module.in.strings["api_infrastructure_role_arn"]
       }
   ```

   ALB 要多一個 target group，由 module 自己建：名稱是 `<name>-<container_port>-alt`（範本是 `cicd-dev-api-8080-alt`，最多 32 字元），listener rule 改成同時轉到兩個 target group（權重 100／0），部署時 ECS 會改這兩個權重。`loadbalancer` stack 不用改。
3. 既有的 service 從 rolling 改成 blue/green 時，module 裡的 service 與 listener rule 會換位址（`aws_ecs_service.pipeline_managed[0]` 換成 `blue_green[0]`，`aws_lb_listener_rule.this[0]` 換成 `blue_green[0]`），直接 apply 會刪掉重建 service。要原地修改，先在 `application` 加 `moved`，plan 確認是 update 而不是 replace 再 apply：

   ```hcl
   moved {
     from = module.api.aws_ecs_service.pipeline_managed[0]
     to   = module.api.aws_ecs_service.blue_green[0]
   }

   moved {
     from = module.api.aws_lb_listener_rule.this[0]
     to   = module.api.aws_lb_listener_rule.blue_green[0]
   }
   ```

   ECS 是否接受把既有 service 原地改成 blue/green，沒有在真實環境確認；module 的測試只涵蓋一開始就用 `BLUE_GREEN` 建立。新環境直接用 `BLUE_GREEN` 建，不會有這個問題。
4. 一起改 `iam` 與 `application` 的測試（role 清單、SSM key、`deployment` 的期望值），再跑 `check-ssm-contract.sh` 與 `scripts/validate.sh`。

還沒確認的事：部署後 service 的 `load_balancer.target_group_arn` 會不會跟 alternate 互換（會的話下一次 `terraform plan` 會想改回來）；`aws ecs wait services-stable` 會不會在 bake time 結束前就回傳；`api-deploy` 的 role 在 blue/green 下需不需要更多權限。採用前要在 dev 驗證。

## 執行 apply 的身分要有的權限

除了建立各資源的一般權限，下面幾項容易漏。清單依 AWS 文件整理，沒有對真實帳號核對：

| 權限 | 哪個 stack | 說明 |
|---|---|---|
| `ecr:BatchGetImage`、`ecr:GetDownloadUrlForLayer` | `application` | fn 的 role 沒有 ECR 權限；Lambda 建立函式時，靠執行 apply 的身分拉 `bootstrap` 映像（跟 example6 相同）。沒有在真實帳號確認 |
| `iam:PassRole`（api 的兩個 role、fn 的 role） | `application` | 把 role 交給 ECS 與 Lambda |
| `iam:PassRole`（5 個建置 role、pipeline role） | `pipeline` | 把 role 交給 CodeBuild 與 CodePipeline |
| `codeconnections:PassConnection` | `pipeline` | 建 pipeline 時把 connection 交給 CodePipeline |
| `kms:CreateGrant`、`kms:Decrypt` | `application`、`pipeline` | log group、建置專案、artifact 用共用 CMK |

## destroy

`./stacks.sh <env> all destroy` 依反向順序跑。先停掉正在跑的 pipeline，下面幾種資源會擋住，要先處理：

| 資源 | 預設 | 要先做什麼 |
|---|---|---|
| 前端 bucket（`web`） | `force_destroy = false` | pipeline 部署過就不是空的，刪不掉。先清空 |
| CloudFront distribution（`web`） | Terraform 先停用再刪除 | 停用要等部署完成，`web` 的 destroy 會花十幾分鐘 |
| api service、task definition（`application`） | | Terraform 只 deregister 自己註冊的版本。pipeline 註冊的版本不在 state 裡，destroy 後還是 `ACTIVE`，要清掉就自己 deregister |
| fn 函式（`application`） | | pipeline 發布的版本會跟函式一起刪掉 |
| ALB（`loadbalancer`） | dev 關、sit 開 deletion protection | sit 先把 `deletion_protection = false` apply 進去再 destroy |
| artifact bucket（`foundation`） | `force_destroy = false`，物件 30 天過期 | 執行過 pipeline 就有物件，刪不掉。先清空 |
| GitHub connection（`foundation`） | | 刪掉後重建要再授權一次。GitHub 上的 App 不會跟著移除，不用了就到 GitHub 的 organization 設定移除 |
| ECR repository（`containerimage`） | `force_delete = false` | `bootstrap` 與 pipeline 推的映像都在，刪不掉。先清空 |
| CMK（`foundation`） | 刪除等待 30 天 | 其他 stack 都拆完再 destroy `foundation`，不然 log 與 artifact 解不開 |

destroy 不會刪範本以外建的東西：state bucket、應用程式 repo 裡的 buildspec、GitHub 上的 App 與 branch protection、pipeline 的 Lambda 部署 action 建的 log group `/ap-northeast-1/codepipeline/<prefix>-fn`。

## 複製出去之後要改什麼

| 項目 | 改什麼 |
|---|---|
| module 的 `source` | 從 HCP private registry 引用（`app.terraform.io/libterty/<module>/aws`，ADR-0004）；換 organization 或改 git 來源見 [`docs/guides/consuming-modules.md`](../../../docs/guides/consuming-modules.md) |
| 帳號表 | 8 個 stack 的 `common.tf` 的 `accounts_by_env`（`111111111111`、`222222222222`），同步改、保持一字不差 |
| state | 每份 `envs/*.tfbackend` 的 `bucket`、`kms_key_id`，`key` 的 `cicd-` 前綴換成自己的 `project`。state bucket 的強化做法見 [example4 REFERENCE〈前置作業的細節〉第 1 項](../../example4/infra/REFERENCE.md#前置作業的細節) |
| 每份 tfvars | `project`（現在是 `cicd`）、`expected_account_id` |
| `foundation` | `alarm_emails`（現在是 `platform-alerts@example.com`） |
| `network` | `vpc_cidr`（`10.30.0.0/16`，不要跟其他 VPC 重疊）、`azs`、`nat_mode` |
| `loadbalancer` | `app_port`（要跟 `application` 一致）、`deletion_protection` |
| `application` | `app_port`、`api_desired_count`、`api_cpu`、`api_memory`、`api_health_check_path`、`fn_memory_size`、`fn_timeout`、`log_retention_days`；`api_bootstrap_image_tag`、`fn_bootstrap_image_tag` 只在第一次建立時用 |
| `pipeline` | `repository`（`example-org/example-app`）、`branch`（`develop`、`main`）、`approval_required`、`fn_deploy_strategy`、`log_retention_days`；buildspec 路徑與專案的環境變數在 `builds.tf` |
| `containerimage` | `lifecycle_rules`：留夠可以回滾的映像 |
| 命名規則 | cluster、service、函式、前端 bucket、建置專案、pipeline 的名稱在 `iam/naming.tf` 與各自的 stack 各一份，要一起改 |

## 已知限制的細節

下面是 mock 驗不到或刻意不做的事，第一次 apply 時要逐項確認。

| 範圍 | 限制 |
|---|---|
| connection 授權 | apply 完是 `PENDING`，要有人在 console 授權（〈GitHub connection 的授權〉）；沒授權時 Source stage 失敗 |
| 不自動觸發 | 依 CodePipeline 文件，`DetectChanges = "false"` 加上沒有 trigger 時 push 不會啟動 pipeline。真實環境要確認 push 之後 pipeline 不會自己跑 |
| `pipeline_managed` | api 與 fn 的設定變動要等下一次對應的 pipeline 才部署；state 跟實際版本不同（〈Terraform 的設定變動什麼時候生效〉） |
| Lambda 部署 action | 沒有 input artifact、只用 `PublishedTargetVersion` 切 alias 的寫法照文件寫，沒有在真實帳號跑過；沒有設 `Alarms`，canary 期間不會依告警自動回滾 |
| `IMAGE_URI` 的傳遞 | api 的 Deploy action 用 `EnvironmentVariables` 帶入 `#{BuildVariables.IMAGE_URI}`，覆寫專案層級變數的行為沒有在真實帳號確認 |
| 失敗告警 | EventBridge rule 用 `detail.pipeline` 比對 pipeline 名稱，沒有用真實的 event 確認 |
| IAM | 各 role 的動作清單、task definition 用 tag 與 family 限定範圍、`UpdateService` 的條件、assume role 時帶的 pipeline ARN、Lambda 部署 action 的 log group `/<region>/codepipeline/<pipeline>` 都依文件寫，沒有對真實帳號驗證 |
| CodeBuild 的權限 | 等於部署分支寫入者的權限（〈branch protection〉）；`--source-revisions` 能不能指定分支外的 commit 沒有確認 |
| 第一次部署 | `bootstrap` 映像不存在時，Lambda 建不起來，ECS 也拉不到映像（design K10） |
| Lambda 拉映像 | fn 的 role 沒有 ECR 權限，靠執行 apply 的身分；pipeline 更新映像時靠 `fn-build` 的身分，這兩種情況是否還需要 repository policy，沒有在真實帳號確認 |
| blue/green | target group 互換、既有 service 原地改策略都沒有確認（〈改用 blue/green〉）；範本用 rolling，只影響採用的專案 |
| 前端 | 沒有 WAF、沒有 CloudFront log、沒有自訂網域；S3 部署 action 不刪舊檔 |
| 內部 ALB | 只有 HTTP，只能從 VPC 內連；沒有 access log 與 WAF |
| 範例 buildspec | 沒有在真實的 CodeBuild 跑過；`jq` 是否內建、`CODEBUILD_RESOLVED_SOURCE_VERSION` 是否為 commit ID 都沒有確認 |
| CodeConnections 的價格 | 價目頁上找不到收費項目，沒有確認 |

## 驗證

```bash
scripts/validate.sh templates/example9/infra/terraform
```

依序做 `fmt`、靜態規則（含 S1 mock provider、S8 stack 只呼叫 module、S10 lock 的 darwin 與 linux hash、S11 terraform-docs）、`check-ssm-contract.sh`；再對每個 stack 跑 `init -backend=false`、`validate`、`terraform test`（`dev`、`sit` 兩份 tfvars 各一次），最後 tflint。全部離線，不需要 AWS 憑證，但需要 HCP registry token。

### 靜態驗證通過（2026-10-30）

| 項目 | 結果 |
|---|---|
| `fmt`、靜態規則（含 S11）與 tflint | 通過 |
| `init -backend=false`、`validate` | 8 個 stack 通過 |
| `terraform test` | 8 個 stack、16 個測試檔跑 24 次（主測試 1 次，tfvars 測試 `dev`、`sit` 各 1 次），202 個 run 全過 |
| `check-ssm-contract.sh` | 8 個 stack、38 個讀取、2 個 env 通過 |
| `stacks.sh dev all plan --dry-run` | 依 ORDER 印出 8 個 stack 的指令，`destroy` 反向 |

### 雲端整合待驗證

需要真實帳號，這個里程碑沒有做。

| 項目 | 怎麼確認 |
|---|---|
| connection | 授權後狀態是 `AVAILABLE`；Source stage 拿得到程式碼 |
| 不自動觸發 | push 到 `develop` 之後，三條 pipeline 都沒有自己跑 |
| api pipeline | `IMAGE_URI` 從 Build 傳到 Deploy；`api-deploy` 註冊的新版本保留 Terraform 的設定；service 穩定後 pipeline 成功；故意部署壞的映像時 circuit breaker 回滾、pipeline 失敗並送告警 |
| fn pipeline | `VERSION` 傳到 Lambda 部署 action；dev 直接切換，sit 照 canary 10% 5 分鐘切換 |
| web pipeline | S3 部署 action 寫進前端 bucket；invalidation 只對這個 distribution 有權限；CloudFront 網址看得到新版本 |
| sit 的 Approval | pipeline 停在 Approval；只有 `PutApprovalResult` 的人能核准；拒絕時 pipeline 失敗 |
| IAM | 每個建置 role 只能動自己的元件；pipeline role 的 Lambda 部署 log 寫得進 `/<region>/codepipeline/<prefix>-fn` |
| 第一次 apply | `bootstrap` 映像存在時，`application` 建得起 service 與函式；ECS task 通過 ALB health check |
| 失敗告警 | pipeline 失敗時告警 topic 收到信 |
| destroy | 前端 bucket、artifact bucket、ECR、sit 的 ALB 照〈destroy〉的預期擋住 |
