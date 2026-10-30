# example9 雲端驗證 runbook

## 結論

`templates/example9` 第一次在真實 AWS 帳號 apply 時，照這份 runbook 逐項確認。做完之後，REFERENCE〈雲端整合待驗證〉表、〈已知限制的細節〉與 design v11 §11、§14 裡的「未確認」就能改成有證據的結論。

- 範圍：REFERENCE 表上的 10 項，加上 design §2、§5.4、§11、§14 與 REFERENCE 其他段落裡表上沒涵蓋的 8 項（本文 S1–S8）。
- 每一項都有：前提（要 apply 哪些 stack、tfvars 怎麼設）、指令、預期結果、結果紀錄。
- 指令預設都是唯讀。會改變狀態的指令標【寫入】，只在 `dev` 執行。sit 只做唯讀的設定檢查；sit 才有的行為（Approval、Lambda canary）在 dev 暫時改 tfvars 重現，做完改回來。
- 這份文件的指令都**沒有實際跑過**，名稱與數值都從程式碼推出來，出處寫在每段的「名稱怎麼來的」。標「推測」的是 repo 以外的慣例（AWS 的預設命名或行為），執行時以實際輸出為準。
- 從程式碼看，第一次驗證最可能卡在這兩件事：
  1. **Lambda 部署 action 不帶 input artifact**（`pipeline/pipelines.tf:69-84`）：只靠 `PublishedTargetVersion` 切 alias 是照文件寫的，沒有實例可以對照。第 4 項會直接驗證。
  2. **`api-deploy` 的 buildspec 依賴 `jq`**：CodeBuild 的 `amazonlinux-aarch64-standard:3.0` 有沒有內建它，REFERENCE 自己也寫了還沒確認（REFERENCE.md:259）。沒有的話，第 3 項會因為 `jq: command not found` 失敗，結果記在 S1。
- 寫這份 runbook 時查過 AWS service authorization reference（2026-10-30，`servicereference.us-east-1.amazonaws.com/v1/<service>/<service>.json`）：
  - `ecs:RegisterTaskDefinition` 的 resource type 是 `task-definition`，所以 `iam/policies.tf:109-114` 限定在 api family 的寫法有文件支持；`ecs:DescribeTaskDefinition` 沒有 resource type，程式碼用 `*` 是對的。S2 仍用 policy simulator 確認一次。
  - `cloudfront:CreateInvalidation` 的 resource type 是 `distribution`，`distribution` 支援 `aws:ResourceTag/${TagKey}`，所以 web 的 invalidation 用 tag 限定範圍也有文件支持。S3 確認實際行為。

## 範圍

涵蓋：

| 編號 | 項目 | 來源 |
|---|---|---|
| 1–10 | connection、不自動觸發、api pipeline、fn pipeline、web pipeline、sit 的 Approval、IAM、第一次 apply、失敗告警、destroy | `templates/example9/infra/REFERENCE.md:580-595`〈雲端整合待驗證〉 |
| S1–S8 | 表上沒涵蓋、散在其他段落的未確認事項（對照見下表） | design §2、§5.4、§11、§14；REFERENCE〈已知限制的細節〉〈範例 buildspec〉〈執行 pipeline〉〈改用 blue/green〉 |

design 與 REFERENCE 各個「未確認」的去處：

| 來源 | 內容 | 在本文 |
|---|---|---|
| design §2 第 6 點、§11 第 1 點 | connection 要在 console 授權 | 第 1 項 |
| design §2 第 7 點、§11 第 2 點、§14〈查證結果〉 | `DetectChanges = "false"` 加上沒有 trigger，push 不會觸發 | 第 2 項 |
| design §14〈查證結果〉 | `QUEUED` 只有 V2 能用 | 第 2 項 |
| design §14〈查證結果〉 | pipeline role 同時要 `codeconnections:` 與 `codestar-connections:UseConnection` | 第 1 項 |
| design §14〈範本〉`pipeline` | api-deploy 用 `EnvironmentVariables` 覆寫 `IMAGE_URI` | 第 3 項 |
| design §2 第 2 點、§14〈範本〉`pipeline` | Lambda 部署 action 不給 input artifact，只靠 `PublishedTargetVersion` | 第 4 項 |
| design §14〈範本〉`pipeline` | 失敗事件用 pipeline 名稱比對 | 第 9 項 |
| design §11 第 3、4 點 | `pipeline_managed` 的 drift；Terraform 的設定變動要等下一次 pipeline | S4 |
| design §11 第 5 點、§5.4、§14〈module〉`ecs-service` | blue/green 的 target group 互換、listener rule 權重 100／0 | S7 |
| design §14〈範本〉、REFERENCE〈改用 blue/green〉 | rolling 改 blue/green 的 `moved` 寫法；ECS infrastructure role 的 trust 不帶 `source_account` | S7 |
| design §11 第 6 點、§4.1 | CodeBuild 的權限等於部署分支寫入者的權限 | S6（branch protection）；第 7 項、S2、S3（每個 role 的範圍） |
| design §14〈範本〉`iam` | task definition 限定 api family、web-invalidate 用 tag 限定 | S2、S3 |
| design §11 第 7 點 | 第一次部署需要 `bootstrap` 映像 | 第 8 項 |
| design §11 第 8 點 | destroy 會被擋住的資源 | 第 10 項 |
| design §14〈module〉`lambda-function` | `aws_lambda_permission` 沒有 qualifier | S8 |
| REFERENCE〈已知限制的細節〉Lambda 拉映像 | fn role 沒有 ECR 權限，靠 apply 身分與 `fn-build` 的身分 | S5 |
| REFERENCE〈範例 buildspec〉 | 5 份範例沒在 CodeBuild 跑過；`jq`、`CODEBUILD_RESOLVED_SOURCE_VERSION` | S1（環境），第 3–5 項（各自的 buildspec） |
| REFERENCE〈執行 pipeline〉 | `--source-revisions` 能不能指定分支外的 commit | S6 |
| REFERENCE〈執行 pipeline〉 | 執行、核准的 IAM 範例 | 第 6 項 |
| REFERENCE〈已知限制的細節〉IAM | Lambda 部署 action 的 log group `/<region>/codepipeline/<pipeline>` | 第 7 項 |
| REFERENCE〈執行 apply 的身分要有的權限〉 | apply 身分容易漏的權限 | 第 8 項（記錄 apply 失敗的訊息） |

不涵蓋：

- CodeConnections 的價格（REFERENCE.md:560）：要看帳單，一次驗證答不出來。一個月後到 Cost Explorer 依服務篩 CodeConnections 確認。
- 內部 ALB 沒有 HTTPS、access log、WAF，前端沒有 WAF、log、自訂網域（REFERENCE.md:557-558）：刻意不做，不需要驗證。
- Lambda 部署 action 沒有設 `Alarms`（REFERENCE.md:549）：刻意不做；第 4 項只記錄 canary 期間不會自動回滾。

## 需要的權限與工具

工具：

- AWS CLI v2（要有 `codeconnections`、`codepipeline list-action-executions`、`iam simulate-principal-policy`）、`jq`、`curl`、Terraform（apply 用）、`docker`（推 `bootstrap` 映像，arm64 build）。
- `gh`（GitHub CLI），只用唯讀的 `gh api` 看 branch protection（S6）。
- 應用程式 repo（範本佔位 `example-org/example-app`）的寫入權限，第 2 項要 push 一個不影響功能的 commit 到 `develop`。

身分：

| 用途 | 身分 | 依據 |
|---|---|---|
| apply 8 個 stack | 各 stack 的 apply 身分，權限見 REFERENCE〈執行 apply 的身分要有的權限〉 | REFERENCE.md:494-504 |
| 授權 GitHub connection | 同時能更新 connection 的 AWS 身分，與 GitHub organization owner（或能安裝 GitHub App 的人） | REFERENCE.md:168 |
| 執行 pipeline | 有 REFERENCE〈誰能執行、誰能核准〉的執行權限 | REFERENCE.md:347-385 |
| 核准（第 6 項） | 另一個只有 `PutApprovalResult` 加 `GetPipelineState` 的身分；沒有的話用執行身分，但「沒權限的人不能核准」那段就跳過 | REFERENCE.md:387-396 |
| 執行本文的唯讀指令 | 下面列的唯讀權限 | 無 |

驗證身分要的 AWS 權限（唯讀）：`sts:GetCallerIdentity`、`ssm:GetParameter`、`codeconnections:GetConnection`、`codepipeline:GetPipeline`、`codepipeline:GetPipelineState`、`codepipeline:GetPipelineExecution`、`codepipeline:ListPipelineExecutions`、`codepipeline:ListActionExecutions`、`codebuild:BatchGetBuilds`、`codebuild:BatchGetProjects`、`logs:DescribeLogGroups`、`logs:GetLogEvents`、`logs:FilterLogEvents`、`ecs:Describe*`、`ecs:List*`、`elasticloadbalancing:Describe*`、`application-autoscaling:DescribeScalableTargets`、`lambda:GetFunction`、`lambda:GetFunctionConfiguration`、`lambda:GetAlias`、`lambda:ListVersionsByFunction`、`lambda:GetPolicy`、`ecr:DescribeImages`、`ecr:GetRepositoryPolicy`、`s3:ListBucket`、`s3:GetObject`、`cloudfront:GetDistribution`、`cloudfront:ListInvalidations`、`cloudfront:ListTagsForResource`、`events:DescribeRule`、`events:ListTargetsByRule`、`events:TestEventPattern`、`sns:ListSubscriptionsByTopic`、`cloudwatch:GetMetricStatistics`、`iam:GetRole`、`iam:GetRolePolicy`、`iam:ListAttachedRolePolicies`、`iam:SimulatePrincipalPolicy`、`iam:SimulateCustomPolicy`、`cloudtrail:LookupEvents`、`kms:DescribeKey`、`elasticloadbalancing:DescribeLoadBalancerAttributes`。

【寫入】要另外的權限：`codepipeline:StartPipelineExecution`、`codepipeline:PutApprovalResult`、`codebuild:StartBuild`（S2 的探測建置）、`ecs:UpdateService`、`lambda:UpdateAlias`、`lambda:InvokeFunction`、`lambda:AddPermission`、`lambda:RemovePermission`、`events:PutRule`、`events:PutTargets`、`events:RemoveTargets`、`events:DeleteRule`（S8）、`ecr:BatchDeleteImage`、`s3:DeleteObject`（第 10 項），以及 ECR 推映像的權限。

網路：ALB 是內部的（`loadbalancer/alb.tf:8`），只收 VPC CIDR 的 80（`loadbalancer/security-groups.tf:10-16`）。第 3、8 項要打 api 的 `/health` 時，在 VPC 內的機器上跑 `curl`；沒有的話只看 target health，不打 HTTP。CloudFront 是公開網址，任何地方都能測。

## 共用變數

每次開新的 shell 先跑這段。`<project>`、`<env>` 換成 tfvars 的值（範本是 `cicd`；env 是 `dev` 或 `sit`）。stack 還沒 apply 的話，它的 key 會回 `ParameterNotFound`，那幾行先略過。

```bash
export AWS_REGION=ap-northeast-1          # common.tf:24，aws_region 預設值；改過就跟著改
P=<project>                               # tfvars 的 project
E=<env>                                   # dev 或 sit
PFX="$P-$E"
ssm() { aws ssm get-parameter --name "/$P/$E/$1" --query Parameter.Value --output text; }

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
API_REPO=$(ssm containerimage/api_repository_url)
FN_REPO=$(ssm containerimage/fn_repository_url)
KMS_ARN=$(ssm foundation/kms_key_arn)
ARTIFACT_BUCKET=$(ssm foundation/artifact_bucket_name)
TOPIC_ARN=$(ssm foundation/alert_topic_arn)
CONN_ARN=$(ssm foundation/connection_arn)
CLUSTER=$(ssm application/cluster_name)
SERVICE=$(ssm application/api_service_name)
FAMILY=$(ssm application/api_task_family)
FN=$(ssm application/fn_function_name)
ALIAS=$(ssm application/fn_alias_name)
WEB_BUCKET=$(ssm web/web_bucket_name)
DIST_ID=$(ssm web/distribution_id)
API_PL=$(ssm pipeline/api_pipeline_name)
FN_PL=$(ssm pipeline/fn_pipeline_name)
WEB_PL=$(ssm pipeline/web_pipeline_name)
role_arn() { echo "arn:aws:iam::$ACCOUNT:role/$PFX-$1"; }

# 最近一次執行的 ID
latest() { aws codepipeline list-pipeline-executions --pipeline-name "$1" --max-results 1 \
  --query 'pipelineExecutionSummaries[0].pipelineExecutionId' --output text; }
# 某次執行裡每個 action 的狀態、輸出變數、解析後的設定、CodeBuild 的 build ID
actions() { aws codepipeline list-action-executions --pipeline-name "$1" --filter pipelineExecutionId="$2" \
  --query 'actionExecutionDetails[].{stage:stageName,action:actionName,status:status,vars:output.outputVariables,config:input.resolvedConfiguration,build:output.executionResult.externalExecutionId}' --output json; }
# 某個 CodeBuild build 的 log
buildlog() { read -r g s < <(aws codebuild batch-get-builds --ids "$1" --query 'builds[0].logs.[groupName,streamName]' --output text)
  aws logs get-log-events --log-group-name "$g" --log-stream-name "$s" --query 'events[].message' --output text; }
```

名稱怎麼來的：

- 名稱前綴：`common.tf:44` 的 `name_prefix = "${var.project}-${var.env}"`，8 個 stack 的 `common.tf` 一樣。
- SSM 路徑：`common.tf:45` 的 `ssm_prefix = "/${var.project}/${var.env}"`，`modules/ssm-publish/main.tf:4` 組成 `<ssm_prefix>/<stack>/<key>`。key 見 `containerimage/ssm-outputs.tf:3-4`、`foundation/ssm-outputs.tf:3-6`、`application/ssm-outputs.tf:4-8`、`web/ssm-outputs.tf:4-5`、`pipeline/ssm-outputs.tf:4-6`。
- role 名稱 `<prefix>-<後綴>`：`iam/roles.tf:7-9`、`:12`、`:19`（建置專案的 role 是 `<專案名稱>-codebuild`）。

## 執行順序

順序照 `stacks.sh:8` 的 `ORDER` 與 REFERENCE〈第一次 apply〉。每個 stack 先跑 `--dry-run` 看一次指令。

| 階段 | 做什麼 | 做完接著驗 |
|---|---|---|
| 0 | 照 README〈複製出去之後要改什麼〉換掉佔位值；`foundation` 的 `alarm_emails` 換成會收信的地址；`pipeline` 的 `repository`、`branch` 換成真的 repo；應用程式 repo 放好 5 份 buildspec（REFERENCE〈範例 buildspec〉） | 無 |
| A | `./stacks.sh <env> containerimage apply`、`foundation apply` | 第 1 項的 `PENDING` 部分；點 SNS 確認信 |
| B | 在 console 授權 connection（REFERENCE〈GitHub connection 的授權〉） | 第 1 項 |
| C | 推 api、fn 的 `bootstrap` 映像（REFERENCE.md:122-142 的指令） | 第 8 項的映像部分 |
| D | `network`、`iam`、`loadbalancer`、`application` | 第 8 項、S5 |
| E | `web`、`pipeline` | 第 2 項的設定部分、第 9 項的 pattern 部分 |
| F | 手動執行 api、fn、web 三條 pipeline（dev） | 第 3–5 項、第 7 項、S1、S2、S3 |
| G | push 一個 commit 到 `develop` | 第 2 項的實測部分 |
| H | dev 暫時改 `approval_required = true`、`fn_deploy_strategy = "Canary10Percent5Minutes"`，apply `pipeline` 再跑 | 第 6 項、第 4 項的 canary、第 9 項的實測 |
| I | dev 改 `application` 的設定再 apply、再跑 pipeline | S4 |
| J | `--source-revisions`、branch protection | S6 |
| K | Lambda permission 實驗（選做） | S8 |
| L | dev 改成 blue/green | S7 |
| M | sit 照 A–F 再做一次 | 第 1、2、6 項的 sit 唯讀檢查 |
| N | dev destroy | 第 10 項 |

H 做完要把 dev 的 `pipeline` tfvars 改回 `approval_required = false`、`fn_deploy_strategy = "AllAtOnce"`（`pipeline/envs/dev.tfvars:8-9`）再 apply。

---

## 1. connection

**前提**

- 階段 A 已 apply。`foundation` 建 connection `<prefix>-github`，type `GitHub`（`foundation/connection.tf:4-5`）。
- 授權照 REFERENCE.md:164-185。安裝範圍只勾應用程式 repo。

**指令**

```bash
# 授權前：PENDING
aws codeconnections get-connection --connection-arn "$CONN_ARN" \
  --query 'Connection.{name:ConnectionName,status:ConnectionStatus,provider:ProviderType}'

# 授權後（階段 B）：AVAILABLE
aws codeconnections get-connection --connection-arn "$CONN_ARN" --query Connection.ConnectionStatus --output text

# pipeline role 對 connection 的兩種前綴
aws iam get-role-policy --role-name "$PFX-pipeline" --policy-name permissions --output json \
  | jq '.PolicyDocument.Statement[] | select(.Sid=="UseGitHubConnection")'

# 階段 F 之後：Source stage 拿到程式碼、commit 是分支最新的
EXEC=$(latest "$API_PL")
actions "$API_PL" "$EXEC" | jq '.[] | select(.stage=="Source") | {status, vars}'
```

名稱怎麼來的：connection 名稱 `"${local.name_prefix}-github"`（`foundation/connection.tf:4`）；inline policy 名稱是 `permissions`（`iam/policies.tf:263`、`modules/iam-role-policy/main.tf:8`）；Sid `UseGitHubConnection`（`iam/policies.tf:207-211`），第二個 ARN 是把 `:codeconnections:` 換成 `:codestar-connections:`；Source action 的 namespace `SourceVariables`（`modules/codepipeline/main.tf:18`）。

**預期結果**

- apply 完 `status` 是 `PENDING`、`provider` 是 `GitHub`；授權後是 `AVAILABLE`。
- policy 的 `Action` 有 `codeconnections:UseConnection` 與 `codestar-connections:UseConnection`，`Resource` 是兩個 ARN（前綴不同、其餘相同）。
- Source action `Succeeded`，`vars` 有 `CommitId`、`BranchName`（CodeStarSourceConnection 的輸出變數，推測），`BranchName` 是 tfvars 的 `branch`，`CommitId` 等於這個分支當下最新的 commit（`git ls-remote origin <branch>` 對照）。
- 不通過時記下 Source action 的錯誤訊息（例如沒授權的 `connection is not available`、GitHub App 沒裝到這個 repo）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 2. 不自動觸發

**前提**

- 階段 E 完成。module 固定 `DetectChanges = "false"`（`modules/codepipeline/main.tf:13`）、`pipeline_type = "V2"`（`:27`）、`execution_mode` 預設 `QUEUED`（`:28`、`modules/codepipeline/variables.tf:139`），沒有 `trigger` 區塊。
- 實測（階段 G）要能 push 一個不影響功能的 commit 到 `develop`（例如改 README）。

**指令**

```bash
for pl in "$API_PL" "$FN_PL" "$WEB_PL"; do
  aws codepipeline get-pipeline --name "$pl" --output json | jq --arg pl "$pl" '{
    pl: $pl,
    type: .pipeline.pipelineType,
    mode: .pipeline.executionMode,
    triggers: (.pipeline.triggers // []),
    detect: (.pipeline.stages[0].actions[0].configuration.DetectChanges),
    stages: [.pipeline.stages[].name]}'
done

# 每次執行是誰啟動的
for pl in "$API_PL" "$FN_PL" "$WEB_PL"; do
  echo "== $pl"
  aws codepipeline list-pipeline-executions --pipeline-name "$pl" --max-results 10 \
    --query 'pipelineExecutionSummaries[].[startTime,status,trigger.triggerType,sourceRevisions[0].revisionId]' --output text
done
```

【寫入】實測：push 一個 commit 到 `develop`，記下時間與 commit ID，等 15 分鐘再跑一次上面的 `list-pipeline-executions`。

```bash
# 15 分鐘內有沒有 CodePipeline 自己啟動的執行
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=StartPipelineExecution \
  --start-time "$(date -u -v-30M +%FT%TZ 2>/dev/null || date -u -d '-30 min' +%FT%TZ)" --output json \
  | jq -r '.Events[].CloudTrailEvent | fromjson | "\(.eventTime) \(.userIdentity.type) \(.userIdentity.arn // .userIdentity.invokedBy) \(.requestParameters.name)"'
```

`QUEUED` 的行為（【寫入】，dev）：對 web pipeline 連按兩次執行，再看執行清單。

```bash
aws codepipeline start-pipeline-execution --name "$WEB_PL"
aws codepipeline start-pipeline-execution --name "$WEB_PL"
aws codepipeline list-pipeline-executions --pipeline-name "$WEB_PL" --max-results 3 \
  --query 'pipelineExecutionSummaries[].[pipelineExecutionId,status,startTime]' --output text
```

名稱怎麼來的：pipeline 名稱 `<prefix>-api`、`-fn`、`-web`（`pipeline/pipelines.tf:6-10`，跟 `iam/naming.tf:41-45` 一致）；stage 名稱 `Source`（`modules/codepipeline/main.tf:3`）、`Build`、`Approval`、`Deploy`、`Invalidate`（`pipeline/pipelines.tf:14`、`:29`、`:41`、`:103`、`:114`）。

**預期結果**

- 三條都是 `type = V2`、`mode = QUEUED`、`triggers = []`、`detect = "false"`。
- dev 的 stage：api、fn 是 `Source, Build, Deploy`，web 是 `Source, Build, Deploy, Invalidate`；sit 在 `Build` 與 `Deploy` 之間多 `Approval`。
- 每筆執行的 `triggerType` 都是 `StartPipelineExecution`（人按的），沒有 `CloudWatchEvent`、`WebhookV2`、`PutActionRevision` 這類自動觸發（triggerType 名稱是 CodePipeline 的命名，推測）。
- push 之後 15 分鐘內三條 pipeline 都沒有新的執行；CloudTrail 裡的 `StartPipelineExecution` 都是人的身分。
- 連按兩次時，第二次不會讓第一次變成 `Superseded`；第一次跑完後第二次才繼續，兩次最後都是 `Succeeded`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／push 的 commit ______

## 3. api pipeline

**前提**

- 階段 F：dev 的 api pipeline 至少成功一次。應用程式 repo 有 `buildspec/api-build.yml`、`buildspec/api-deploy.yml`（照 REFERENCE.md:206-255）。
- api 的映像要在 8080 回應 `GET /health`（REFERENCE.md:142）。
- Build action 的 namespace 是 `BuildVariables`（`pipeline/pipelines.tf:24`、`:36`）；Deploy action 用 `EnvironmentVariables` 帶 `IMAGE_URI = #{BuildVariables.IMAGE_URI}`（`pipeline/pipelines.tf:46-49`）。`api-deploy` 專案本身沒有 `IMAGE_URI` 變數（`pipeline/builds.tf:23-29`），所以 pipeline 是新加這個變數，沒有專案層級的值被蓋掉。

**指令**

```bash
# 【寫入】
aws codepipeline start-pipeline-execution --name "$API_PL"
# 等 get-pipeline-state 的每個 stage 都是 Succeeded
aws codepipeline get-pipeline-state --name "$API_PL" --query 'stageStates[].[stageName,latestExecution.status]' --output text

EXEC=$(latest "$API_PL")
actions "$API_PL" "$EXEC" | jq '.[] | {stage, status, vars, env: .config.EnvironmentVariables, build}'

# service 現在用的版本，和它的映像
TD=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query 'services[0].taskDefinition' --output text)
echo "$TD"
aws ecs describe-task-definition --task-definition "$TD" --query 'taskDefinition.containerDefinitions[?name==`app`].image' --output text

# 新版本保留 Terraform 的設定：跟前一版比，除了映像以外都一樣
REV=${TD##*:}
diff <(aws ecs describe-task-definition --task-definition "$FAMILY:$((REV-1))" --include TAGS --output json \
        | jq -S 'del(.taskDefinition.taskDefinitionArn,.taskDefinition.revision,.taskDefinition.registeredAt,.taskDefinition.registeredBy,.taskDefinition.containerDefinitions[0].image)') \
     <(aws ecs describe-task-definition --task-definition "$TD" --include TAGS --output json \
        | jq -S 'del(.taskDefinition.taskDefinitionArn,.taskDefinition.revision,.taskDefinition.registeredAt,.taskDefinition.registeredBy,.taskDefinition.containerDefinitions[0].image)') \
  && echo "除了映像以外相同"

# service 穩定
aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].{desired:desiredCount,running:runningCount,deployments:deployments[].{status:status,rollout:rolloutState,td:taskDefinition}}'
TG_ARN=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query 'services[0].loadBalancers[0].targetGroupArn' --output text)
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output text
```

`REV-1` 是這次 pipeline 之前的最後一版：第一次跑 pipeline 時是 Terraform 註冊的版本，之後可能是上一次 pipeline 註冊的。不管是哪一種，都應該只有映像不同。

【寫入】circuit breaker：部署一個啟動就結束的映像，只在 dev 做。兩種做法擇一：

- 在 `develop` 上放一個短期的 commit，讓 api 的 Dockerfile `CMD` 直接 `exit 1`，跑 api pipeline，記錄完 revert 再跑一次。這個做法會順便驗到第 9 項。
- 不動分支：手動推一個壞映像 `$API_REPO:broken-<日期>`，用 `api-deploy` 專案直接跑一次（推測 `--source-type-override NO_SOURCE` 也能用在 `CODEPIPELINE` 類型的專案；不行就用第一種）：

  ```bash
  aws codebuild start-build --project-name "$PFX-api-deploy" \
    --source-type-override NO_SOURCE --artifacts-override type=NO_ARTIFACTS \
    --buildspec-override file://api-deploy.yml \
    --environment-variables-override name=IMAGE_URI,value="$API_REPO:broken-<日期>",type=PLAINTEXT
  ```

  `api-deploy.yml` 是把 REFERENCE.md:228-255 那份存到本機的檔案。

```bash
aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].{deployments:deployments[].{status:status,rollout:rolloutState,reason:rolloutStateReason,td:taskDefinition},events:events[:10].message}'
```

名稱怎麼來的：service 與 family `"${local.name_prefix}-api"`（`application/api.tf:8`，family 用 service 名稱是 `modules/ecs-service/main.tf:111`）；cluster `local.name_prefix`（`application/cluster.tf:3`）；container 名稱固定 `app`（`modules/ecs-service/main.tf:13`、`pipeline/builds.tf:28`）；target group `"${var.name}-${var.container_port}"` 也就是 `<prefix>-api-8080`（`modules/ecs-service/load-balancer.tf:15`）；建置專案 `<prefix>-api-build`、`<prefix>-api-deploy`（`pipeline/builds.tf:6-7`）；rolling 100%／200% 與 circuit breaker rollback（`modules/ecs-service/main.tf:256-262`）。

**預期結果**

- Build action 的 `vars.IMAGE_URI` 是 `<api repo URL>:<commit 前 12 碼>-<建置編號>`。
- Deploy action 的 `env`（`resolvedConfiguration.EnvironmentVariables`）裡 `IMAGE_URI` 已經是實際的 URI，不是字面上的 `#{BuildVariables.IMAGE_URI}`。
- service 用的 task definition 映像等於 `IMAGE_URI`。
- `diff` 印出「除了映像以外相同」：CPU、記憶體、role、log 設定、port、tag 都跟前一版一樣。
- `deployments` 只剩一個 `PRIMARY`、`rollout` 是 `COMPLETED`；`running` 等於 `desired`（dev 1、sit 2：`application/envs/*.tfvars:15`）；target 都是 `healthy`。
- 壞映像：新的 deployment `rollout` 變 `FAILED`，`reason` 提到 circuit breaker，service 回到原本的 task definition；`aws ecs wait services-stable` 回傳失敗（或 10 分鐘逾時），build 跟著失敗。走 pipeline 的做法時，pipeline 執行是 `Failed`，會收到第 9 項的告警信。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／用了哪種壞映像做法 ______

## 4. fn pipeline

**前提**

- 階段 F：dev 的 fn pipeline 至少成功一次。應用程式 repo 有 `buildspec/fn-build.yml`（REFERENCE.md:261-281）。
- Deploy action 是 `category = "Deploy"`、`provider = "Lambda"`，沒有 `input_artifacts`，`PublishedTargetVersion = #{BuildVariables.VERSION}`，`DeployStrategy = var.fn_deploy_strategy`（`pipeline/pipelines.tf:69-84`）。dev 是 `AllAtOnce`、sit 是 `Canary10Percent5Minutes`（`pipeline/envs/dev.tfvars:9`、`sit.tfvars:9`）。
- canary 實測在階段 H：dev 暫時改 `fn_deploy_strategy = "Canary10Percent5Minutes"`，apply `pipeline`。

**指令**

```bash
# 跑之前 alias 指的版本
aws lambda get-alias --function-name "$FN" --name "$ALIAS" --query '{v:FunctionVersion,r:RoutingConfig}'

# 【寫入】
aws codepipeline start-pipeline-execution --name "$FN_PL"
aws codepipeline get-pipeline-state --name "$FN_PL" --query 'stageStates[].[stageName,latestExecution.status]' --output text

EXEC=$(latest "$FN_PL")
actions "$FN_PL" "$EXEC" | jq '.[] | {stage, status, vars, config}'

# alias、$LATEST 的映像、版本清單
aws lambda get-alias --function-name "$FN" --name "$ALIAS" --query '{v:FunctionVersion,r:RoutingConfig}'
aws lambda get-function --function-name "$FN" --query 'Code.ImageUri' --output text
aws lambda list-versions-by-function --function-name "$FN" --query 'Versions[].[Version,LastModified]' --output text

# Lambda 部署 action 的 log
aws logs describe-log-groups --log-group-name-prefix "/$AWS_REGION/codepipeline/$FN_PL" --query 'logGroups[].logGroupName'
aws logs filter-log-events --log-group-name "/$AWS_REGION/codepipeline/$FN_PL" --limit 20 --query 'events[].message' --output text
```

【寫入】呼叫 alias 一次，確認新版本真的能跑：

```bash
aws lambda invoke --function-name "$FN" --qualifier "$ALIAS" --payload '{}' --cli-binary-format raw-in-base64-out /dev/stdout \
  --query '{status:StatusCode,err:FunctionError,ver:ExecutedVersion}'
```

canary（階段 H）：跑 fn pipeline，Deploy action 開始後每分鐘看一次 alias，總共 7 分鐘。

```bash
aws lambda get-alias --function-name "$FN" --name "$ALIAS" --query '{v:FunctionVersion,r:RoutingConfig.AdditionalVersionWeights}'
```

sit（唯讀）：

```bash
aws codepipeline get-pipeline --name "$P-sit-fn" \
  --query 'pipeline.stages[?name==`Deploy`].actions[0].configuration' --output json
```

名稱怎麼來的：函式 `"${local.name_prefix}-fn"`、alias `live`（`application/function.tf:8`、`:14`）；Terraform 忽略 `$LATEST` 的映像，也忽略 alias 的 `function_version` 與 `routing_config`（`modules/lambda-function/main.tf:90-92`、`:116-118`）；Lambda 部署 action 的 log group `/<region>/codepipeline/<pipeline>`（`iam/policies.tf:256`，REFERENCE.md:522）；`fn-build` 專案的變數 `REPOSITORY_URI`、`FUNCTION_NAME`（`pipeline/builds.tf:34-37`）。

**預期結果**

- Build action 的 `vars.VERSION` 是一個數字（新發布的版本）。
- Deploy action `Succeeded`；`config.PublishedTargetVersion` 是那個數字，不是字面上的 `#{BuildVariables.VERSION}`；action 沒有 input artifact 也能跑。
- dev（`AllAtOnce`）：Deploy 完 alias 的 `v` 等於 `VERSION`，`r` 是空的；`$LATEST` 的映像是這次推的 tag。
- `invoke` 的 `status` 是 200、沒有 `err`，`ver` 等於 `VERSION`。
- log group `/ap-northeast-1/codepipeline/<prefix>-fn` 存在且有這次的 log。
- canary：前 5 分鐘 alias 的 `v` 還是舊版本、`r` 是 `{"<VERSION>": 0.1}`；5 分鐘後 `v` 變成 `VERSION`、`r` 清空（canary 期間的呈現方式是推測，以實際輸出為準）。
- sit 的 `DeployStrategy` 是 `Canary10Percent5Minutes`，沒有 `Alarms`。
- 不通過時記下 Deploy action 的錯誤訊息，特別是「需要 input artifact」或缺權限這類。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／canary 期間 alias 的實際樣子 ______

## 5. web pipeline

**前提**

- 階段 F：dev 的 web pipeline 至少成功一次。應用程式 repo 有 `buildspec/web-build.yml`、`buildspec/web-invalidate.yml`（REFERENCE.md:283-315），`npm run build` 輸出在 `dist`。
- S3 部署 action `Extract = "true"`，input 是 `BuildArtifact`（`pipeline/pipelines.tf:103-110`）；`Invalidate` stage 跑 `web-invalidate`（`:112-121`）。

**指令**

```bash
# 跑之前前端 bucket 的內容（第一次是空的）
aws s3 ls "s3://$WEB_BUCKET/" --recursive | head

# 【寫入】
aws codepipeline start-pipeline-execution --name "$WEB_PL"
aws codepipeline get-pipeline-state --name "$WEB_PL" --query 'stageStates[].[stageName,latestExecution.status]' --output text

aws s3 ls "s3://$WEB_BUCKET/" --recursive | head -20
aws cloudfront list-invalidations --distribution-id "$DIST_ID" --max-items 3 \
  --query 'InvalidationList.Items[].[Id,Status,CreateTime]' --output text

DOMAIN=$(aws cloudfront get-distribution --id "$DIST_ID" --query Distribution.DomainName --output text)
curl -s -o /dev/null -w '%{http_code}\n' "https://$DOMAIN/"
curl -s -o /dev/null -w '%{http_code}\n' "https://$DOMAIN/some/spa/route"
# CloudFront 給的 index.html 跟 bucket 裡的一樣
diff <(curl -s "https://$DOMAIN/index.html") <(aws s3 cp "s3://$WEB_BUCKET/index.html" -) && echo "index.html 相同"
# bucket 不能直接讀
curl -s -o /dev/null -w '%{http_code}\n' "https://$WEB_BUCKET.s3.$AWS_REGION.amazonaws.com/index.html"
```

名稱怎麼來的：前端 bucket `"${local.name_prefix}-web-${var.expected_account_id}"`（`web/buckets.tf:6`）；distribution 名稱 `<prefix>-web`（`web/distribution.tf:5`）；SPA fallback 的 CloudFront Function `<prefix>-web-spa-fallback`（`modules/cloudfront-distribution/main.tf:47`）；建置專案 `<prefix>-web-build`、`<prefix>-web-invalidate`（`pipeline/builds.tf:9-10`）。

**預期結果**

- 跑完後 bucket 裡是 `dist` 底下的結構（`index.html` 在根目錄，不是 `dist/index.html`）。
- 有一筆這次執行建立的 invalidation，狀態 `Completed`（buildspec 等它完成才結束）。
- `/` 與 SPA 路徑都是 `200`；`index.html` 相同。
- bucket 直接讀是 `403`。
- 再跑一次 pipeline 時，舊檔案還在 bucket 裡（S3 部署 action 只上傳不刪，REFERENCE.md:317）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 6. sit 的 Approval

**前提**

- dev（階段 H）：`pipeline/envs/dev.tfvars` 暫時改 `approval_required = true`，apply `pipeline`。Approval stage 名稱 `Approval`、action `Approve`、`CustomData` 是「部署到 <env> 之前請確認」（`pipeline/pipelines.tf:13-21`）。
- 核准身分照 REFERENCE.md:387-396。再準備一個沒有 `PutApprovalResult` 的身分（例如只有執行權限的人），用來測「不能核准」。

**指令**

```bash
# sit（唯讀）：三條都有 Approval，而且在 Build 與 Deploy 之間
for c in api fn web; do
  aws codepipeline get-pipeline --name "$P-sit-$c" --query 'pipeline.stages[].name' --output text
done

# REFERENCE 的核准 policy 對得上 action 的 ARN（唯讀）
cat > approve.json <<JSON
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["codepipeline:PutApprovalResult"],
 "Resource":"arn:aws:codepipeline:$AWS_REGION:$ACCOUNT:$PFX-*/Approval/Approve"}]}
JSON
aws iam simulate-custom-policy --policy-input-list file://approve.json --action-names codepipeline:PutApprovalResult \
  --resource-arns "arn:aws:codepipeline:$AWS_REGION:$ACCOUNT:$API_PL/Approval/Approve" \
  --query 'EvaluationResults[0].EvalDecision' --output text
```

【寫入】dev 實測：

```bash
aws codepipeline start-pipeline-execution --name "$API_PL"
# 停在 Approval
aws codepipeline get-pipeline-state --name "$API_PL" --query 'stageStates[].[stageName,latestExecution.status]' --output text
TOKEN=$(aws codepipeline get-pipeline-state --name "$API_PL" \
  --query "stageStates[?stageName=='Approval'].actionStates[0].latestExecution.token" --output text)

# 用沒有 PutApprovalResult 的身分：應該 AccessDenied
aws codepipeline put-approval-result --pipeline-name "$API_PL" --stage-name Approval --action-name Approve \
  --result summary="runbook",status=Approved --token "$TOKEN"

# 用核准身分：通過，pipeline 繼續到 Deploy
aws codepipeline put-approval-result --pipeline-name "$API_PL" --stage-name Approval --action-name Approve \
  --result summary="runbook 核准",status=Approved --token "$TOKEN"

# 再跑一次，這次拒絕
aws codepipeline start-pipeline-execution --name "$API_PL"
TOKEN=$(aws codepipeline get-pipeline-state --name "$API_PL" \
  --query "stageStates[?stageName=='Approval'].actionStates[0].latestExecution.token" --output text)
aws codepipeline put-approval-result --pipeline-name "$API_PL" --stage-name Approval --action-name Approve \
  --result summary="runbook 拒絕",status=Rejected --token "$TOKEN"
aws codepipeline list-pipeline-executions --pipeline-name "$API_PL" --max-results 2 \
  --query 'pipelineExecutionSummaries[].[pipelineExecutionId,status]' --output text
```

拒絕的那次會觸發第 9 項的告警，一起看信。做完把 `approval_required` 改回 `false` 並 apply。

名稱怎麼來的：stage、action 名稱與 `approval_required`（`pipeline/pipelines.tf:13-21`、`pipeline/variables.tf:21-24`）；核准 policy 的 resource 格式 `<pipeline>/<stage>/<action>`（REFERENCE.md:387-396）。

**預期結果**

- sit 三條的 stage：api、fn 是 `Source Build Approval Deploy`，web 是 `Source Build Approval Deploy Invalidate`。
- `simulate-custom-policy` 回 `allowed`。
- dev 實測：執行停在 `Approval` 的 `InProgress`；沒有權限的身分得到 `AccessDeniedException`；核准後 Deploy 開始；拒絕的那次執行是 `Failed`。
- Approval 沒人處理時 7 天後會失敗（REFERENCE.md:339），這次不驗；需要的話留一個不處理，7 天後再看。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 7. IAM

**前提**

- 階段 F 完成（三條 pipeline 都跑過）。
- 每個 role 的權限在 `iam/policies.tf:62-254`。這一項先用 policy simulator 檢查範圍（唯讀，只看 identity policy），再用 CloudTrail 看實際執行有沒有被拒絕。task definition 與 CloudFront 的細節在 S2、S3。

**指令**

```bash
sim() {  # sim <role 後綴> <action> <resource> [context entry...]
  local r; r=$(role_arn "$1"); shift
  local a=$1 res=$2; shift 2
  printf '%-28s %-34s %-12s %s\n' "${r##*/}" "$a" \
    "$(aws iam simulate-principal-policy --policy-source-arn "$r" --action-names "$a" --resource-arns "$res" \
       ${1:+--context-entries "$@"} --query 'EvaluationResults[0].EvalDecision' --output text)" "${res##*:}"
}
API_REPO_ARN="arn:aws:ecr:$AWS_REGION:$ACCOUNT:repository/$PFX-api"
FN_REPO_ARN="arn:aws:ecr:$AWS_REGION:$ACCOUNT:repository/$PFX-fn"
FN_ARN="arn:aws:lambda:$AWS_REGION:$ACCOUNT:function:$FN"
SAME=ContextKeyName=aws:ResourceAccount,ContextKeyValues=$ACCOUNT,ContextKeyType=string

# 每個建置 role 只能動自己的元件
sim api-build-codebuild      ecr:PutImage               "$API_REPO_ARN"     # allowed
sim api-build-codebuild      ecr:PutImage               "$FN_REPO_ARN"      # implicitDeny
sim fn-build-codebuild       ecr:PutImage               "$FN_REPO_ARN"      # allowed
sim fn-build-codebuild       ecr:PutImage               "$API_REPO_ARN"     # implicitDeny
sim fn-build-codebuild       lambda:UpdateFunctionCode  "$FN_ARN"           # allowed
sim fn-build-codebuild       lambda:UpdateFunctionCode  "${FN_ARN}-other"   # implicitDeny
sim web-build-codebuild      s3:PutObject               "arn:aws:s3:::$WEB_BUCKET/index.html" "$SAME"       # implicitDeny
sim web-build-codebuild      s3:PutObject               "arn:aws:s3:::$ARTIFACT_BUCKET/x" "$SAME"           # allowed
sim api-deploy-codebuild     s3:PutObject               "arn:aws:s3:::$ARTIFACT_BUCKET/x" "$SAME"           # implicitDeny
sim web-invalidate-codebuild s3:PutObject               "arn:aws:s3:::$ARTIFACT_BUCKET/x" "$SAME"           # implicitDeny
sim api-build-codebuild      secretsmanager:GetSecretValue "arn:aws:secretsmanager:$AWS_REGION:$ACCOUNT:secret:x"  # implicitDeny

# pipeline role
for k in api-build api-deploy fn-build web-build web-invalidate; do
  sim pipeline codebuild:StartBuild "arn:aws:codebuild:$AWS_REGION:$ACCOUNT:project/$PFX-$k"   # allowed
done
sim pipeline codebuild:StartBuild "arn:aws:codebuild:$AWS_REGION:$ACCOUNT:project/$PFX-other"  # implicitDeny
sim pipeline lambda:UpdateAlias   "$FN_ARN:$ALIAS"                                             # allowed
sim pipeline lambda:UpdateAlias   "${FN_ARN}-other:$ALIAS"                                     # implicitDeny
sim pipeline s3:PutObject         "arn:aws:s3:::$WEB_BUCKET/index.html" "$SAME"                # allowed
sim pipeline logs:PutLogEvents    "arn:aws:logs:$AWS_REGION:$ACCOUNT:log-group:/$AWS_REGION/codepipeline/$FN_PL:log-stream:x"  # allowed

# 實際執行：這些 role 有沒有被拒絕過（最近 24 小時）
for r in api-build-codebuild api-deploy-codebuild fn-build-codebuild web-build-codebuild web-invalidate-codebuild pipeline; do
  echo "== $r"
  aws cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue="$r" \
    --start-time "$(date -u -v-24H +%FT%TZ 2>/dev/null || date -u -d '-24 hour' +%FT%TZ)" --max-results 200 --output json \
    | jq -r '.Events[].CloudTrailEvent | fromjson | select(.errorCode != null) | "\(.eventTime) \(.eventName) \(.errorCode)"'
done

# trust：每個建置 role 只信任自己的專案
for r in api-build api-deploy fn-build web-build web-invalidate; do
  aws iam get-role --role-name "$PFX-$r-codebuild" --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition' --output json
done
aws iam get-role --role-name "$PFX-pipeline" --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition' --output json
```

assumed role 在 CloudTrail 的 `Username` 是 session 名稱還是 role 名稱，依服務而定（推測）。查不到東西時改用 `AttributeKey=EventName` 搭配 `jq` 篩 `.userIdentity.sessionContext.sessionIssuer.userName`。

名稱怎麼來的：role 名稱（`iam/roles.tf:7-21`）；trust 的 `aws:SourceAccount` 與 `aws:SourceArn`（`iam/roles.tf:14`、`:21`、`:34`，條件的組法在 `modules/iam-role/main.tf:32-35`）；repository 名稱 `<prefix>-api`、`<prefix>-fn`（`containerimage/repositories.tf:5-6`）；artifact bucket `<prefix>-artifacts-<account>`（`foundation/buckets.tf:6`）；各 Sid 與動作（`iam/policies.tf:89-253`）；只有 3 個建置專案能寫 artifact（`iam/policies.tf:29`、`:48`）。

**預期結果**

- `sim` 的結果跟每行後面的註解一致。
- 三條 pipeline 跑過之後，6 個 role 的 CloudTrail 都沒有 `AccessDenied`。有的話記下 `eventName`，那就是漏給的權限。
- 建置 role 的 trust 條件是 `StringEquals aws:SourceAccount = <account>` 加 `ArnLike aws:SourceArn = arn:aws:codebuild:<region>:<account>:project/<自己的專案>`；pipeline role 是 `arn:aws:codepipeline:<region>:<account>:<prefix>-*`。
- 第 4 項的 log group 有寫進 log，代表 `LambdaDeployLogGroup`、`LambdaDeployLogEvents` 兩個 statement 夠用。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／漏給的權限 ______

## 8. 第一次 apply

**前提**

- 階段 C 推了 `bootstrap`（`application/envs/*.tfvars:9-10`），階段 D apply 完 `application`。
- ECS service 建立時不等穩定（`modules/ecs-service/main.tf:267`），要自己看 task。
- `api_desired_count` 由 scalable target 管（`min = max = desired_count`，`modules/ecs-service/autoscaling.tf:30-36`），service 本身忽略 `desired_count`。

**指令**

```bash
# 兩個 repository 都有 bootstrap，tag 不可覆寫
for r in "$PFX-api" "$PFX-fn"; do
  aws ecr describe-repositories --repository-names "$r" --query 'repositories[0].[repositoryName,imageTagMutability,encryptionConfiguration.encryptionType]' --output text
  aws ecr describe-images --repository-name "$r" --image-ids imageTag=bootstrap --query 'imageDetails[0].[imageTags,imagePushedAt]' --output text
done

# service、task、target
aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].{status:status,desired:desiredCount,running:runningCount,td:taskDefinition,lb:loadBalancers,events:events[:5].message}'
aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE" --query 'taskArns' --output text \
  | xargs -n 10 aws ecs describe-tasks --cluster "$CLUSTER" --query 'tasks[].[lastStatus,healthStatus,cpu,memory,attributes[?name==`ecs.cpu-architecture`].value|[0]]' --output text --tasks
aws elbv2 describe-target-groups --names "$PFX-api-8080" --query 'TargetGroups[0].[TargetGroupName,Port,HealthCheckPath,TargetType]' --output text
aws elbv2 describe-target-health --target-group-arn "$(aws elbv2 describe-target-groups --names "$PFX-api-8080" --query 'TargetGroups[0].TargetGroupArn' --output text)" \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason]' --output text
aws application-autoscaling describe-scalable-targets --service-namespace ecs --resource-ids "service/$CLUSTER/$SERVICE" \
  --query 'ScalableTargets[0].[MinCapacity,MaxCapacity]' --output text

# 函式、版本、alias
aws lambda get-function --function-name "$FN" --query '{state:Configuration.State,arch:Configuration.Architectures,mem:Configuration.MemorySize,timeout:Configuration.Timeout,image:Code.ImageUri}'
aws lambda get-alias --function-name "$FN" --name "$ALIAS" --query FunctionVersion --output text

# log group 用 CMK、保存天數
aws logs describe-log-groups --log-group-name-prefix "/ecs/$SERVICE" --query 'logGroups[].[logGroupName,retentionInDays,kmsKeyId]' --output text
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/$FN" --query 'logGroups[].[logGroupName,retentionInDays,kmsKeyId]' --output text
aws logs describe-log-groups --log-group-name-prefix "/aws/ecs/containerinsights/$CLUSTER/" --query 'logGroups[].[logGroupName,retentionInDays]' --output text
```

在 VPC 內的機器（選做）：

```bash
ALB_DNS=$(aws elbv2 describe-load-balancers --names "$PFX-alb" --query 'LoadBalancers[0].DNSName' --output text)
curl -s -o /dev/null -w '%{http_code}\n' "http://$ALB_DNS/health"
```

名稱怎麼來的：repository（`containerimage/repositories.tf:5-6`），`IMMUTABLE` 與 AES256（`modules/ecr-repository/main.tf:3`、`:11`）；target group `<prefix>-api-8080`（`modules/ecs-service/load-balancer.tf:15`）；health check `/health`（`application/variables.tf:57`）；ALB `<prefix>-alb`（`loadbalancer/alb.tf:7`）；log group `/ecs/<service>`（`modules/ecs-service/main.tf:5`）、`/aws/lambda/<name>`（`modules/lambda-function/main.tf:7`）、`/aws/ecs/containerinsights/<cluster>/performance`（`modules/ecs-cluster/main.tf:29`）；arm64（`application/function.tf:11`，ECS 預設 `ARM64`：`modules/ecs-service/variables.tf:57`）；記憶體與逾時預設 512、30（`application/variables.tf:63`、`:69`）。

**預期結果**

- 兩個 repository 都是 `IMMUTABLE`、`AES256`，都有 `bootstrap`。
- service `ACTIVE`，`running` 等於 dev 1／sit 2；task `RUNNING`、cpu `256`、memory `512`、架構 `arm64`。
- target group `<prefix>-api-8080`、port `8080`、path `/health`、type `ip`；target 都 `healthy`。
- scalable target 的 min 與 max 都等於 `api_desired_count`。
- 函式 `Active`、`arm64`、512、30，映像是 `<fn repo>:bootstrap`；alias `live` 指到 `1`。
- 三個 log group 的保存天數是 dev 30／sit 90；`/ecs/` 與 `/aws/lambda/` 的 `kmsKeyId` 是共用 CMK。
- `curl` 回 `200`。
- apply 過程中如果因為權限失敗（REFERENCE〈執行 apply 的身分要有的權限〉的那幾項），把錯誤訊息和補上的權限記在備註。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／apply 補過的權限 ______

## 9. 失敗告警

**前提**

- 階段 E 完成；SNS 的 email 訂閱已確認。
- rule `<prefix>-pipeline-failed`：`source = aws.codepipeline`、`detail-type = CodePipeline Pipeline Execution State Change`、`detail.pipeline` 是三條 pipeline、`detail.state = FAILED`，target 是告警 topic（`pipeline/alerts.tf:4-13`、`:24`）。
- topic 放行 `events.amazonaws.com` 發布（`foundation/alerts.tf:7`），CMK 放行 `events.amazonaws.com`（`foundation/kms.tf:18`）。

**指令**

```bash
aws events describe-rule --name "$PFX-pipeline-failed" --query '{state:State,pattern:EventPattern}'
aws events list-targets-by-rule --rule "$PFX-pipeline-failed" --query 'Targets[].Arn' --output text
aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" --query 'Subscriptions[].[Protocol,Endpoint,SubscriptionArn]' --output table

# pattern 對真實格式的事件：FAILED 要命中，SUCCEEDED 與其他 pipeline 不命中（唯讀）
PATTERN=$(aws events describe-rule --name "$PFX-pipeline-failed" --query EventPattern --output text)
ev() { jq -nc --arg pl "$1" --arg st "$2" --arg acct "$ACCOUNT" --arg r "$AWS_REGION" '{
  version:"0", id:"00000000-0000-0000-0000-000000000000", "detail-type":"CodePipeline Pipeline Execution State Change",
  source:"aws.codepipeline", account:$acct, time:"2026-10-30T00:00:00Z", region:$r,
  resources:["arn:aws:codepipeline:\($r):\($acct):\($pl)"],
  detail:{pipeline:$pl, "execution-id":"x", state:$st, version:1}}'; }
aws events test-event-pattern --event-pattern "$PATTERN" --event "$(ev "$API_PL" FAILED)"      # true
aws events test-event-pattern --event-pattern "$PATTERN" --event "$(ev "$WEB_PL" FAILED)"      # true
aws events test-event-pattern --event-pattern "$PATTERN" --event "$(ev "$API_PL" SUCCEEDED)"   # false
aws events test-event-pattern --event-pattern "$PATTERN" --event "$(ev "$P-other-api" FAILED)" # false
```

實測：第 6 項拒絕的那次，或第 3 項走 pipeline 的壞映像那次，執行會是 `Failed`。之後看：

```bash
for m in TriggeredRules Invocations FailedInvocations; do
  printf '%-18s ' "$m"
  aws cloudwatch get-metric-statistics --namespace AWS/Events --metric-name "$m" --dimensions Name=RuleName,Value="$PFX-pipeline-failed" \
    --start-time "$(date -u -v-2H +%FT%TZ 2>/dev/null || date -u -d '-2 hour' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
    --period 3600 --statistics Sum --query 'Datapoints[].Sum' --output text
done
```

事件欄位（`detail.pipeline`、`detail.state`）照 CodePipeline 文件的格式，上面的 `ev` 也照這個格式組（推測，以收到的信為準）。

名稱怎麼來的：rule 名稱（`pipeline/alerts.tf:5`）；topic `<prefix>-alerts`（`foundation/alerts.tf:3`）；`TriggeredRules` 等是 EventBridge 的指標名稱（推測）。

**預期結果**

- rule `ENABLED`，pattern 跟上面一致；target 是 `<prefix>-alerts` 的 ARN。
- 訂閱的 `SubscriptionArn` 是完整 ARN，不是 `PendingConfirmation`。
- 四個 `test-event-pattern` 依序是 `true`、`true`、`false`、`false`。
- 實測：`TriggeredRules`、`Invocations` 有值、`FailedInvocations` 沒有值；收到 email，內容是 pipeline 的事件 JSON，`detail.pipeline` 是失敗的那條。
- 收到信時，把 JSON 裡 `detail` 的實際欄位貼在備註，確認 pattern 的欄位名稱。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／信裡的 detail ______

## 10. destroy

**前提**

- 只在 dev 做，而且是這次驗證的最後一步。三條 pipeline 都跑過（bucket 與 repository 有東西），沒有正在跑的執行。
- sit 只做唯讀檢查（ALB 的刪除保護）。
- `stacks.sh` 的 destroy 依 `ORDER` 反向（`stacks.sh:7-8`），任何一個 stack 失敗就停（README.md:42）。

**指令**

```bash
# sit（唯讀）：ALB 的刪除保護是開的
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn "$(aws elbv2 describe-load-balancers --names "$P-sit-alb" --query 'LoadBalancers[0].LoadBalancerArn' --output text)" \
  --query 'Attributes[?Key==`deletion_protection.enabled`].Value' --output text

# dev：destroy 之前記下 pipeline 註冊的 task definition 版本
aws ecs list-task-definitions --family-prefix "$FAMILY" --status ACTIVE --query 'taskDefinitionArns' --output text
```

【寫入】dev：

```bash
cd templates/example9/infra/terraform    # 複製出去的專案就是 infra/terraform
./stacks.sh dev all destroy
```

每次停下來，記下是哪個 stack、什麼錯誤，照 REFERENCE.md:510-520 處理後再跑一次：

```bash
aws s3 rm "s3://$WEB_BUCKET" --recursive            # web 停在前端 bucket
aws s3 rm "s3://$ARTIFACT_BUCKET" --recursive       # foundation 停在 artifact bucket
for r in "$PFX-api" "$PFX-fn"; do                   # containerimage 停在 repository
  ids=$(aws ecr list-images --repository-name "$r" --query 'imageIds' --output json)
  [ "$ids" != "[]" ] && aws ecr batch-delete-image --repository-name "$r" --image-ids "$ids"
done
```

全部拆完之後，看留下來的東西：

```bash
aws ecs list-task-definitions --family-prefix "$FAMILY" --status ACTIVE --query 'taskDefinitionArns' --output text
aws logs describe-log-groups --log-group-name-prefix "/$AWS_REGION/codepipeline/" --query 'logGroups[].logGroupName' --output text
aws kms describe-key --key-id "$KMS_ARN" --query 'KeyMetadata.[KeyState,DeletionDate]' --output text
aws codeconnections list-connections --query "Connections[?ConnectionName=='$PFX-github']" --output text
```

名稱怎麼來的：會擋 destroy 的設定：前端 bucket 與 artifact bucket 不 `force_destroy`（`modules/s3-bucket/main.tf:176`，兩個 stack 都沒設），repository `force_delete = false`（`modules/ecr-repository/main.tf:4`），ALB 刪除保護 dev 關、sit 開（`loadbalancer/envs/dev.tfvars:9`、`sit.tfvars:8`）；Lambda 部署 action 的 log group 不在 state 裡（REFERENCE.md:522）。

**預期結果**

- sit 的 `deletion_protection.enabled` 是 `true`。
- dev 的 destroy 依序停在：`web`（前端 bucket 不是空的；CloudFront 停用要十幾分鐘）、`foundation`（artifact bucket 不是空的）、`containerimage`（repository 有映像）。清空後再跑就過。`pipeline`、`application`、`iam`、`loadbalancer`、`network` 不需要先處理。
- 拆完後：pipeline 註冊的 task definition 版本還是 `ACTIVE`；`/ap-northeast-1/codepipeline/<prefix>-fn` 還在；CMK 是 `PendingDeletion`、刪除日在 30 天後；connection 已經不在。
- 實際停下來的順序或原因跟上面不同時，逐一記在備註。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／停下來的 stack 與原因 ______

---

## 其他未確認的項目

### S1. 範例 buildspec 在 CodeBuild 上的環境

**前提**：第 3–5 項都跑過。5 個專案都是 `BUILD_GENERAL1_SMALL`、`ARM_CONTAINER`、`aws/codebuild/amazonlinux-aarch64-standard:3.0`（`modules/codebuild-project/variables.tf:45-47`），`api-build`、`fn-build` 開 privileged 與 Docker layer cache（`pipeline/builds.tf:16`、`:33`、`:60`），buildspec 路徑 `buildspec/<專案 key 的底線換連字號>.yml`（`pipeline/builds.tf:57`）。

**指令**

```bash
for pl in "$API_PL" "$FN_PL" "$WEB_PL"; do
  EXEC=$(latest "$pl")
  COMMIT=$(actions "$pl" "$EXEC" | jq -r '.[] | select(.stage=="Source") | .vars.CommitId')
  for B in $(actions "$pl" "$EXEC" | jq -r '.[] | select(.build != null and (.build | test(":"))) | .build'); do
    aws codebuild batch-get-builds --ids "$B" --output json | jq --arg commit "$COMMIT" '.builds[0] | {
      project: .projectName, status: .buildStatus, image: .environment.image, type: .environment.type,
      commit_match: (.resolvedSourceVersion == $commit), resolved: .resolvedSourceVersion,
      exported: .exportedEnvironmentVariables, buildspec: .source.buildspec}'
  done
done

# api-deploy 的 jq、各專案的 command not found
for k in api-build api-deploy fn-build web-build web-invalidate; do
  echo "== $k"
  aws logs filter-log-events --log-group-name "/aws/codebuild/$PFX-$k" --filter-pattern '"command not found"' \
    --query 'events[].message' --output text
done
```

`actions` 回的 `build` 欄位，在 CodeBuild action 是 build ID（`<專案>:<uuid>`），在 Lambda、S3、Manual action 不是，所以上面用有沒有冒號來篩。

名稱怎麼來的：log group `/aws/codebuild/<name>`（`modules/codebuild-project/main.tf:2`）；專案名稱（`pipeline/builds.tf:5-11`）。

**預期結果**

- 5 個 build 都 `SUCCEEDED`，`image` 與 `type` 跟上面一致，`buildspec` 是 `buildspec/<名稱>.yml`。
- `commit_match` 都是 `true`：`CODEBUILD_RESOLVED_SOURCE_VERSION` 就是 commit ID（REFERENCE.md:202 的假設）。
- `exported`：`api-build` 有 `IMAGE_URI`、`fn-build` 有 `VERSION`，其他沒有。
- 沒有任何 `command not found`，特別要看 `api-deploy` 的 `jq`。有的話，在 REFERENCE 的範例加 `install` phase，並記在備註。
- 推上去的映像是 arm64：`aws ecr describe-images --repository-name "$PFX-api" --image-ids imageTag=<tag>` 的 `artifactMediaType` 與 manifest（`aws ecr batch-get-image`）看得到 `arm64`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／`jq` 是否內建 ______

### S2. api-deploy 的 task definition 權限範圍

**前提**：第 3 項跑過。`api-deploy` 的 role：`DescribeTaskDefinition` 用 `*`；`RegisterTaskDefinition` 與 `TagResource` 限定 `task-definition/<prefix>-api:*`，`TagResource` 另外要 `ecs:CreateAction = RegisterTaskDefinition`；`UpdateService` 限定 api service，條件 `ecs:task-definition` 是 api family；`PassRole` 只有 api 的兩個 role，條件 `iam:PassedToService = ecs-tasks.amazonaws.com`（`iam/policies.tf:101-145`、`iam/naming.tf:47-48`）。`sim` 是第 7 項定義的函式，S3 也用它。

**指令**

```bash
TD_ARN="arn:aws:ecs:$AWS_REGION:$ACCOUNT:task-definition"
SVC_ARN="arn:aws:ecs:$AWS_REGION:$ACCOUNT:service/$CLUSTER/$SERVICE"
sim api-deploy-codebuild ecs:RegisterTaskDefinition "$TD_ARN/$FAMILY:999"                          # allowed
sim api-deploy-codebuild ecs:RegisterTaskDefinition "$TD_ARN/$PFX-other:1"                        # implicitDeny
sim api-deploy-codebuild ecs:TagResource "$TD_ARN/$FAMILY:999" ContextKeyName=ecs:CreateAction,ContextKeyValues=RegisterTaskDefinition,ContextKeyType=string  # allowed
sim api-deploy-codebuild ecs:TagResource "$TD_ARN/$FAMILY:999"                                    # implicitDeny
sim api-deploy-codebuild ecs:UpdateService "$SVC_ARN" ContextKeyName=ecs:task-definition,ContextKeyValues="$TD_ARN/$FAMILY:999",ContextKeyType=string   # allowed
sim api-deploy-codebuild ecs:UpdateService "$SVC_ARN" ContextKeyName=ecs:task-definition,ContextKeyValues="$TD_ARN/$PFX-other:1",ContextKeyType=string  # implicitDeny
sim api-deploy-codebuild ecs:UpdateService "arn:aws:ecs:$AWS_REGION:$ACCOUNT:service/$CLUSTER/$PFX-other" ContextKeyName=ecs:task-definition,ContextKeyValues="$TD_ARN/$FAMILY:999",ContextKeyType=string  # implicitDeny
sim api-deploy-codebuild iam:PassRole "$(role_arn api-task)" ContextKeyName=iam:PassedToService,ContextKeyValues=ecs-tasks.amazonaws.com,ContextKeyType=string  # allowed
sim api-deploy-codebuild iam:PassRole "$(role_arn fn-lambda)" ContextKeyName=iam:PassedToService,ContextKeyValues=ecs-tasks.amazonaws.com,ContextKeyType=string # implicitDeny

# 第 3 項實際的呼叫
for ev in RegisterTaskDefinition TagResource UpdateService; do
  aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue="$ev" --max-results 20 --output json \
    | jq -r --arg r "$PFX-api-deploy-codebuild" '.Events[].CloudTrailEvent | fromjson
      | select(.userIdentity.sessionContext.sessionIssuer.userName == $r)
      | "\(.eventTime) \(.eventName) \(.requestParameters.family // .requestParameters.service // .requestParameters.resourceArn) \(.errorCode // "OK")"'
done
```

【寫入】反向探測（選做，dev）：用 `api-deploy` 專案跑一份只做探測的 buildspec，以這個 role 的身分試著註冊別的 family。`--source-type-override NO_SOURCE` 能不能用，跟第 3 項一樣是推測。

```bash
cat > probe.yml <<'YAML'
version: 0.2
phases:
  build:
    commands:
      - aws ecs describe-task-definition --task-definition "$TASK_FAMILY" --query taskDefinition.containerDefinitions > c.json
      - aws ecs register-task-definition --family "${TASK_FAMILY%-api}-probe" --container-definitions file://c.json --requires-compatibilities FARGATE --network-mode awsvpc --cpu 256 --memory 512 || echo "PROBE_DENIED"
YAML
aws codebuild start-build --project-name "$PFX-api-deploy" --source-type-override NO_SOURCE \
  --artifacts-override type=NO_ARTIFACTS --buildspec-override file://probe.yml --query 'build.id' --output text
# 看 log：應該有 AccessDenied 與 PROBE_DENIED
```

如果探測意外成功，立刻 `aws ecs deregister-task-definition --task-definition <prefix>-probe:1`，結果記為不通過。

名稱怎麼來的：見前提；`TASK_FAMILY` 是 `api-deploy` 的環境變數（`pipeline/builds.tf:26`）。

**預期結果**

- `sim` 的結果跟註解一致。如果第一行 `RegisterTaskDefinition` 對自己的 family 就是 `implicitDeny`，或第 3 項 CloudTrail 的 `RegisterTaskDefinition` 是 `AccessDenied`，代表 ECS 實際上不接受這個動作的 resource-level 限定（跟 service authorization reference 不一致）。這時要改成 `Resource "*"`，靠 `iam:PassRole` 的條件與 `UpdateService` 的 `ecs:task-definition` 條件限制範圍；記在備註並開 issue。
- 第 3 項的 `RegisterTaskDefinition`、`TagResource`、`UpdateService` 都是 `OK`。
- 探測的 build log 有 `AccessDeniedException` 與 `PROBE_DENIED`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／RegisterTaskDefinition 是否支援 resource-level ______

### S3. web-invalidate 的 tag 範圍

**前提**：第 5 項跑過。`web-invalidate` 只能對帶 `Project`、`Environment`、`Managed`、`Stack = web` 這組 tag 的 distribution 做 `CreateInvalidation`、`GetInvalidation`（`iam/policies.tf:166-178`，tag 由 `iam/naming.tf:32` 組成）。distribution 的 tag 來自 `web` provider 的 `default_tags`（`web/providers.tf:16-18`）。

**指令**

```bash
DIST_ARN="arn:aws:cloudfront::$ACCOUNT:distribution/$DIST_ID"
aws cloudfront list-tags-for-resource --resource "$DIST_ARN" --query 'Tags.Items' --output table

tagctx() {  # 四個 tag 的 context，Stack 的值可以換
  printf 'ContextKeyName=aws:ResourceTag/Project,ContextKeyValues=%s,ContextKeyType=string ' "$P"
  printf 'ContextKeyName=aws:ResourceTag/Environment,ContextKeyValues=%s,ContextKeyType=string ' "$E"
  printf 'ContextKeyName=aws:ResourceTag/Managed,ContextKeyValues=terraform,ContextKeyType=string ' 
  printf 'ContextKeyName=aws:ResourceTag/Stack,ContextKeyValues=%s,ContextKeyType=string' "$1"
}
sim web-invalidate-codebuild cloudfront:CreateInvalidation "$DIST_ARN" $(tagctx web)     # allowed
sim web-invalidate-codebuild cloudfront:CreateInvalidation "$DIST_ARN" $(tagctx other)   # implicitDeny
sim web-invalidate-codebuild cloudfront:CreateInvalidation "$DIST_ARN"                   # implicitDeny（沒有 tag）

# 第 5 項實際的呼叫
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=CreateInvalidation --max-results 20 --output json \
  | jq -r '.Events[].CloudTrailEvent | fromjson | "\(.eventTime) \(.userIdentity.arn) \(.requestParameters.distributionId // .requestParameters.id) \(.errorCode // "OK")"'
```

CloudFront 是全域服務，CloudTrail 事件記在 `us-east-1`（推測）；上面查不到時加 `--region us-east-1`。

名稱怎麼來的：見前提；`Managed = "terraform"`（`common.tf:50`）。

**預期結果**

- distribution 有 `Project = <project>`、`Environment = <env>`、`Managed = terraform`、`Stack = web`（另外有 module 加的 `Name`）。
- `sim` 依序是 `allowed`、`implicitDeny`、`implicitDeny`。
- 第 5 項的 `CreateInvalidation` 是 `<prefix>-web-invalidate-codebuild` 的身分、`OK`。如果是 `AccessDenied`，表示 CloudFront 的 `CreateInvalidation` 實際上不吃 `aws:ResourceTag`（跟 service authorization reference 不一致），記在備註。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

### S4. `pipeline_managed` 的 drift 與設定生效時機（design §11 第 3、4 點）

**前提**：第 3、4 項跑過。api service 忽略 `task_definition`、fn 忽略 `image_uri`、alias 忽略版本與流量（`modules/ecs-service/main.tf:272-274`、`modules/lambda-function/main.tf:90-92`、`:116-118`）。

**指令**

```bash
# 1. pipeline 部署過之後，plan 沒有變動
./stacks.sh dev application plan

# 2. state 跟實際不同（REFERENCE〈state 跟實際的差異〉）
aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query 'services[0].taskDefinition' --output text
aws lambda get-alias --function-name "$FN" --name "$ALIAS" --query FunctionVersion --output text
./stacks.sh dev application output
```

【寫入】設定變動要等下一次 pipeline：`application/envs/dev.tfvars` 加 `api_memory = 1024`、`fn_timeout = 31`，apply `application`。

```bash
./stacks.sh dev application apply
# api：family 多一個 Terraform 註冊的版本（映像是 bootstrap），service 還在用 pipeline 的版本
aws ecs list-task-definitions --family-prefix "$FAMILY" --sort DESC --max-items 3 --query 'taskDefinitionArns' --output text
aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query 'services[0].taskDefinition' --output text
# fn：$LATEST 的逾時變 31，alias 指的版本還是 30
aws lambda get-function-configuration --function-name "$FN" --query Timeout
aws lambda get-function-configuration --function-name "$FN" --qualifier "$ALIAS" --query Timeout

# 跑兩條 pipeline 之後
aws codepipeline start-pipeline-execution --name "$API_PL"
aws codepipeline start-pipeline-execution --name "$FN_PL"
TD=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query 'services[0].taskDefinition' --output text)
aws ecs describe-task-definition --task-definition "$TD" --query 'taskDefinition.[memory,containerDefinitions[0].image]' --output text
aws lambda get-function-configuration --function-name "$FN" --qualifier "$ALIAS" --query '[Timeout,Version]' --output text
```

做完把兩個值拿掉，apply `application`，再跑一次兩條 pipeline。

**預期結果**

- 步驟 1 是 `No changes`。
- 步驟 2：service 的版本號大於 Terraform state 裡的版本（`terraform state show` 或 output 看不到 pipeline 的版本）；alias 的版本大於 1。
- apply 之後：family 最新的版本是 Terraform 註冊的、映像是 `bootstrap`，service 不變；`$LATEST` 的逾時是 31，alias 的還是 30。
- 兩條 pipeline 跑完：service 的新版本記憶體 `1024`、映像是 pipeline 剛推的；alias 指到新版本，逾時 31。
- apply 時注意：Terraform 換掉 task definition 會 deregister 它自己上一次註冊的版本。如果那個版本正好是 service 在用的（只會發生在 pipeline 還沒跑過時），記在備註。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

### S5. Lambda 拉映像與 ECR repository policy

**前提**：階段 D 完成，第 4 項跑過。fn 的 execution role 沒有 ECR 權限（`iam/policies.tf:79-87`）；建立函式時 Lambda 用 apply 身分拉 `bootstrap`，pipeline 更新時用 `fn-build` 的身分（REFERENCE.md:555）。`fn-build` 有 fn repository 的 `BatchGetImage`、`GetDownloadUrlForLayer`（`iam/policies.tf:22-25`、`:150-154`）。

**指令**

```bash
aws ecr get-repository-policy --repository-name "$PFX-fn" --query policyText --output text | jq .
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=SetRepositoryPolicy --max-results 20 --output json \
  | jq -r '.Events[].CloudTrailEvent | fromjson | "\(.eventTime) \(.userIdentity.arn) \(.requestParameters.repositoryName) \(.errorCode // "OK")"'
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=UpdateFunctionCode20150331v2 --max-results 20 --output json \
  | jq -r '.Events[].CloudTrailEvent | fromjson | "\(.eventTime) \(.userIdentity.arn) \(.errorCode // "OK") \(.errorMessage // "")"'
```

`UpdateFunctionCode20150331v2` 是 Lambda 在 CloudTrail 的事件名稱格式（推測）；查不到時改用 `jq` 篩 `eventName | startswith("UpdateFunctionCode")`。

**預期結果**

- 記下 repository policy 的實際內容。預期有一條 `lambda.amazonaws.com` 的 `ecr:BatchGetImage`、`ecr:GetDownloadUrlForLayer`，是建立函式時 Lambda 自己加的（推測）；也可能回 `RepositoryPolicyNotFoundException`。
- 如果有 `SetRepositoryPolicy`，記下是哪個身分（apply 身分）。如果 apply 身分沒有 `ecr:SetRepositoryPolicy`，導致建立函式失敗，記下錯誤訊息，補進 REFERENCE〈執行 apply 的身分要有的權限〉。
- `fn-build` 的 `UpdateFunctionCode` 都是 `OK`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／repository policy 的內容 ______

### S6. 部署來源：`--source-revisions` 與 branch protection（design §11 第 6 點）

**前提**：第 5 項跑過。準備一個**不在** `develop` 上的 commit（例如別的分支上的），記下它的 SHA。

**指令**

```bash
# branch protection（唯讀，GitHub）
gh api "repos/<owner>/<repo>/branches/develop/protection" --jq '{reviews: .required_pull_request_reviews.required_approving_review_count, enforce_admins: .enforce_admins.enabled, force_push: .allow_force_pushes.enabled, deletions: .allow_deletions.enabled}'
gh api "repos/<owner>/<repo>/rules/branches/develop" --jq '[.[].type]'
# GitHub App 的安裝範圍：在 organization 的 Settings → GitHub Apps → AWS Connector for GitHub 看 Repository access
```

【寫入】dev：用分支外的 commit 跑 web pipeline（影響最小），之後用分支最新的 commit 再跑一次還原。

```bash
aws codepipeline start-pipeline-execution --name "$WEB_PL" \
  --source-revisions actionName=Source,revisionType=COMMIT_ID,revisionValue=<分支外的 SHA>
EXEC=$(latest "$WEB_PL")
aws codepipeline get-pipeline-execution --pipeline-name "$WEB_PL" --pipeline-execution-id "$EXEC" \
  --query 'pipelineExecution.{status:status,rev:artifactRevisions[0].revisionId}'
actions "$WEB_PL" "$EXEC" | jq '.[] | select(.stage=="Source") | {status, vars}'

aws codepipeline start-pipeline-execution --name "$WEB_PL"
```

**預期結果**

- branch protection：至少一位 reviewer、`enforce_admins` 是 `true`、不允許 force push 與刪除（REFERENCE.md:407）；用 ruleset 的話，rule 清單裡有 `pull_request`、`non_fast_forward`、`deletion`。沒開就記為不通過；上線前一定要開（README.md:60）。
- App 的安裝範圍只有應用程式 repo。
- `--source-revisions`：記下實際結果。如果執行成功、Source 的 `CommitId` 是分支外的 SHA，代表有 `StartPipelineExecution` 權限的人可以部署 repo 裡任何 commit（REFERENCE.md:400 的保守假設成立），在備註寫明。如果被拒絕，記下錯誤訊息。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／分支外 commit 能不能部署 ______

### S7. rolling 改 blue/green（design §5.4、§11 第 5 點、§14）

**前提**

- 只在 dev 做，第 3 項已經通過。程式碼照 REFERENCE.md:445-492 改，只改本機的工作目錄：
  1. `iam/roles.tf` 加 `module "api_ecs_infrastructure_role"`（`iam-role` `~> 0.6.0`，名稱 `<prefix>-api-ecs-infrastructure`，trust `ecs.amazonaws.com`，掛 `arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers`），`iam/ssm-outputs.tf` 加 `api_infrastructure_role_arn`。
  2. `application/ssm-inputs.tf` 加 `api_infrastructure_role_arn`；`application/api.tf:30` 的 `deployment` 改成 `BLUE_GREEN`、`bake_time_in_minutes = 5`、`role_arn`。
  3. `application` 加兩個 `moved`（`pipeline_managed[0]` → `blue_green[0]`、`this[0]` → `blue_green[0]`）。
- module 的行為：alternate target group `<name>-<port>-alt`（`modules/ecs-service/load-balancer.tf:44`），listener rule 轉到兩個 target group 100／0、忽略 `action`（`:100-145`），service 的 `advanced_configuration`（`modules/ecs-service/main.tf:300-310`）、`deployment_configuration.strategy = "BLUE_GREEN"`（`:333-336`），`ignore_changes` 沒有 `load_balancer`（`:350-352`）。

**指令**

```bash
# 1. 【寫入】iam
./stacks.sh dev iam apply
aws iam get-role --role-name "$PFX-api-ecs-infrastructure" --query 'Role.AssumeRolePolicyDocument' --output json
aws iam list-attached-role-policies --role-name "$PFX-api-ecs-infrastructure" --query 'AttachedPolicies[].PolicyArn' --output text
ssm iam/api_infrastructure_role_arn

# 2. application 的 plan：service 與 rule 是原地 update，不是 replace
./stacks.sh dev application plan -- -no-color | tee bg-plan.txt
grep -E 'has moved to|must be replaced|will be (created|destroyed|updated in-place)' bg-plan.txt

# 3. 【寫入】apply，看 service 與 rule
./stacks.sh dev application apply
aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --output json | jq '.services[0] | {
  strategy: .deploymentConfiguration.strategy, bake: .deploymentConfiguration.bakeTimeInMinutes,
  lb: .loadBalancers[0]}'
LISTENER=$(ssm loadbalancer/listener_arn)
show_rule() { aws elbv2 describe-rules --listener-arn "$LISTENER" \
  --query 'Rules[?Priority==`100`].Actions[0].ForwardConfig.TargetGroups[].[TargetGroupArn,Weight]' --output text; }
show_rule

# 4. 【寫入】跑 api pipeline，部署期間每 30 秒看一次 rule 與 deployments
aws codepipeline start-pipeline-execution --name "$API_PL"
show_rule
aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].deployments[].{status:status,rollout:rolloutState,td:taskDefinition,updated:updatedAt}'

# 5. 部署完：service 記錄的 target group 有沒有換、Terraform 想不想改回來
aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query 'services[0].loadBalancers[0].targetGroupArn' --output text
show_rule
./stacks.sh dev application plan

# 6. api-deploy 的 build 什麼時候結束，跟 bake time 比
EXEC=$(latest "$API_PL")
B=$(actions "$API_PL" "$EXEC" | jq -r '.[] | select(.stage=="Deploy") | .build')
aws codebuild batch-get-builds --ids "$B" --query 'builds[0].[startTime,endTime,buildStatus]' --output text
aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query 'services[0].events[:15].[createdAt,message]' --output text
```

第 4 步做兩次（第二次看會不會換回原本的 target group）。也看一次 CloudTrail 有沒有 `api-deploy` 或 infrastructure role 的 `AccessDenied`（第 7 項的迴圈加上 `api-ecs-infrastructure`）。

選做：確認 ECS assume infrastructure role 時有沒有帶 `aws:SourceAccount`。做法是在 `api_ecs_infrastructure_role` 的 trust 加 `source_account = var.expected_account_id`，apply `iam`，再跑一次第 4 步。部署成功代表有帶，可以加回範本。

還原：把 `deployment` 改回 `ROLLING`、`moved` 反過來寫，plan 確認是 update 再 apply；或直接拆掉 dev 重建。如果 plan 要 replace service，記在備註，不要 apply。

名稱怎麼來的：role 名稱與 policy ARN（REFERENCE.md:453-460，ARN 見 design §14〈查證結果〉、`modules/iam-role/locals.tf:28`）；alternate target group `cicd-dev-api-8080-alt`（REFERENCE.md:474）；listener rule priority 100（`application/api.tf:23`）。

**預期結果**

- 步驟 1：trust 是 `ecs.amazonaws.com`、沒有條件；policy 只有 `AmazonECSInfrastructureRolePolicyForLoadBalancers`；SSM key 存在。
- 步驟 2：plan 有兩行 `has moved to`；service 與 listener rule 是 `updated in-place`；新建 alternate target group；**沒有** `must be replaced`、也沒有 service 的 `destroyed`。有 replace 就停下來，記為不通過（REFERENCE.md:489 的未確認成立）。
- 步驟 3：`strategy` 是 `BLUE_GREEN`、`bake` 是 5；`lb.advancedConfiguration` 有 `alternateTargetGroupArn`、`productionListenerRule`、`roleArn`；rule 兩個 target group 權重 100／0。
- 步驟 4：部署中權重從 100／0 切到 0／100；新舊兩組 task 並存約 5 分鐘後舊的停掉；pipeline `Succeeded`，`api-deploy` 沒有 `AccessDenied`。
- 步驟 5：記下 service 的 `targetGroupArn` 是不是變成 `-alt`，以及 `plan` 是否想改 `load_balancer`。會改的話，`blue_green` 版本要加 `ignore_changes = [load_balancer]`（design §5.4 的未確認成立），開 issue。
- 步驟 6：記下 build 的結束時間與 ECS 事件裡「部署完成」的時間差。build 在 bake time 結束前就結束，代表 `aws ecs wait services-stable` 不等 bake time（REFERENCE.md:492）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／target group 是否互換 ______ ／plan 是否想改回 ______ ／wait 是否等 bake ______

### S8. Lambda permission 沒有 qualifier（design §14〈module〉`lambda-function`）

**前提**：example9 沒有傳 `permissions`（`application/function.tf:19-34`），不受影響。這一項確認 module 的行為，給之後要在 alias 上加呼叫端的專案參考。module 的 `aws_lambda_permission` 沒有 `qualifier`（`modules/lambda-function/main.tf:121-130`）。

**指令**

```bash
# example9 的函式沒有 resource policy
aws lambda get-policy --function-name "$FN" 2>&1 | head -2
aws lambda get-policy --function-name "$FN" --qualifier "$ALIAS" 2>&1 | head -2
```

【寫入】選做，dev：照 module 的寫法在沒有 qualifier 的函式上加權限，讓 EventBridge 每分鐘呼叫 alias ARN。

```bash
RULE="$PFX-runbook-alias-test"
RULE_ARN=$(aws events put-rule --name "$RULE" --schedule-expression 'rate(1 minute)' --query RuleArn --output text)
aws lambda add-permission --function-name "$FN" --statement-id runbook-unqualified \
  --action lambda:InvokeFunction --principal events.amazonaws.com --source-arn "$RULE_ARN"
aws events put-targets --rule "$RULE" --targets "Id=alias,Arn=arn:aws:lambda:$AWS_REGION:$ACCOUNT:function:$FN:$ALIAS"
# 5 分鐘後
for m in Invocations FailedInvocations; do
  printf '%-18s ' "$m"
  aws cloudwatch get-metric-statistics --namespace AWS/Events --metric-name "$m" --dimensions Name=RuleName,Value="$RULE" \
    --start-time "$(date -u -v-10M +%FT%TZ 2>/dev/null || date -u -d '-10 min' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
    --period 600 --statistics Sum --query 'Datapoints[].Sum' --output text
done

# 對照：在 alias 上加權限，再等 5 分鐘看一次
aws lambda add-permission --function-name "$FN" --qualifier "$ALIAS" --statement-id runbook-alias \
  --action lambda:InvokeFunction --principal events.amazonaws.com --source-arn "$RULE_ARN"

# 收尾
aws events remove-targets --rule "$RULE" --ids alias
aws events delete-rule --name "$RULE"
aws lambda remove-permission --function-name "$FN" --statement-id runbook-unqualified
aws lambda remove-permission --function-name "$FN" --qualifier "$ALIAS" --statement-id runbook-alias
```

**預期結果**

- example9：兩個 `get-policy` 都是 `ResourceNotFoundException`。
- 實驗：只有沒有 qualifier 的權限時，`FailedInvocations` 有值、alias 沒被呼叫（推測：沒有 qualifier 的 resource policy 不涵蓋 alias ARN）；加上 alias 的權限後 `Invocations` 有值、`FailedInvocations` 沒有。結果相反的話記在備註，module README 的提醒（`modules/lambda-function/README.md:61`）就可以拿掉。
- 收尾後 rule 與兩條權限都不在。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／沒有 qualifier 的權限能不能呼叫 alias ______
