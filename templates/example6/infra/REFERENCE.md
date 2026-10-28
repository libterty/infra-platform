# example6 參考資料

這份是 [`README.md`](./README.md) 的參考資料：README 只放第一次用範本需要的步驟，細節、合約、runbook 與驗證紀錄都在這裡。

狀態：離線驗證通過，還沒在真實帳號 apply 過；第一次 apply 時逐項確認〈驗證〉的「雲端整合待驗證」與〈已知限制的細節〉。設計見 [`docs/design/v9/design-docs.md`](../../../docs/design/v9/design-docs.md) §8、§4.3，實作紀錄見 [`implement-process.md`](../../../docs/design/v9/implement-process.md)。設計與程式碼不一致時以程式碼為準，這份文件照程式碼寫。

## 成本

價格是 2026-10-28 查 AWS 官方價目頁的公開牌價（us-east-1 起算的全域價格，WAF、Route 53、Secrets Manager 不分 region），細節與來源見 [design §10](../../../docs/design/v9/design-docs.md)。

- 閒置時每個環境的固定成本主要是 CloudFront WAF：web ACL 5 美元，加兩個 managed rule group 與一條 rate limit 規則各 1 美元，共 8 美元／月，另加每百萬請求 0.6 美元。
- CloudFront 的 flat-rate Free 方案（月費 0、每月 100 萬請求、100 GB 傳輸、含 5 條 WAF 規則）可能讓 dev／sit 省下這筆 WAF 月費；範本沒有設定 flat-rate，要用的話在 console 對這個 distribution 啟用，並確認規則數在 5 條內。
- 其他固定費用很小：hosted zone 每個約 0.5、兩個 secret 各約 0.4、CMK 約 1。
- 依用量計費、低流量時接近 0：CloudFront、API Gateway HTTP API、Lambda、DynamoDB on-demand、Cognito `ESSENTIALS`（免費額度內的 MAU）、CloudWatch Logs、ECR 儲存。

不用的環境請照〈destroy〉拆掉。

## 檔案

`infra/terraform/` 底下每個 stack 一個目錄，另有 `stacks.sh`（依序跑各 stack）與 `check-ssm-contract.sh`（靜態檢查 SSM 合約與 tfvars 一致性）。每個 stack 的固定檔案跟 example5 相同（`versions.tf`、`providers.tf`、`common.tf`、`ssm-outputs.tf`、`envs/<env>.tfvars`、`envs/<env>.tfbackend`、`tests/`、`.terraform.lock.hcl`；有讀上游的 stack 另有 `ssm-inputs.tf`），`common.tf` 9 個 stack 一字不差，`.tfbackend` 有 `kms_key_id = "<state-kms-key-arn>"`。只有 aws provider，沒有 awscc，也沒有 provider alias：us-east-1 的憑證、WAF、log delivery 由 module 的 `region`／`scope` 決定（design K4）。

## stack 的內容與依賴

apply 順序與 `ORDER` 見 README。下游只讀上游發布的 key。`<prefix>` 是 `<project>-<env>`，`<zone>` 是 `dns` 的 `domain_name`（例如 `dev.example.com`）。

| 順序 | stack | 建的東西 | 讀 |
|---|---|---|---|
| 1 | `containerimage` | ECR repository `<prefix>-api`；加密用 AES256（這時共用 CMK 還不存在）；未加 tag 的映像 7 天刪除、最多留 50 個 | 無 |
| 2 | `foundation` | 共用 CMK（key policy 放行 CloudWatch Logs、CloudWatch、SNS）；告警 SNS topic `<prefix>-alarms`（email 訂閱）；secret 容器 `<prefix>/api-key`、`<prefix>/origin-verify`（CMK 加密，刪除後保留 7 天，值在 Terraform 外寫） | 無 |
| 3 | `dns` | public hosted zone `<zone>` | 無 |
| 4 | `certificate` | `app.<zone>` 的 ACM 憑證，建在 us-east-1，DNS 驗證，等簽發最多 45 分鐘 | dns |
| 5 | `auth` | user pool `<prefix>-users`（`ESSENTIALS`、MFA `OPTIONAL`、email 寄信用 `COGNITO_DEFAULT`）；prefix domain `<domain_prefix>.auth.<region>.amazoncognito.com`；resource server `api`（scope `read`、`write`）；public client `spa`（PKCE，scope `openid`、`email`、`api/read`、`api/write`，callback `https://app.<zone>/callback` 加 `local_dev_origins`） | dns |
| 6 | `data` | DynamoDB table `<prefix>-app`：`PK`、`SK` 都是字串、on-demand、PITR（dev 7 天、sit 35 天）、CMK、deletion protection（dev 關、sit 開） | foundation |
| 7 | `iam` | role `<prefix>-api-lambda`（只信任 `lambda.amazonaws.com`，帶 `aws:SourceAccount`）與它的 policy：這張 table 與 index 的讀寫、兩個 secret 的 `GetSecretValue`、CMK 的 `Decrypt`、`/aws/lambda/<prefix>-api` 的 log 寫入 | foundation、data |
| 8 | `api` | Lambda `<prefix>-api`（arm64、512 MB、10 秒、reserved concurrency dev 10／sit 50、映像 `<repository>:<api_image_tag>`）；HTTP API `<prefix>-api`：JWT authorizer `cognito`（issuer 是 user pool、audience 是 SPA client）、3 條 route（下表）、`$default` stage 的 throttling（dev 50／100、sit 200／400）、access log `/aws/apigateway/<prefix>-api-access`；告警 Lambda `Errors`、API `5xx`（5 分鐘內 ≥ 1） | containerimage、foundation、auth、data、iam |
| 9 | `web` | site bucket `<prefix>-web-<account>`（SSE-S3、不過期、只讓這個 distribution 經 OAC 讀）；CloudFront `<prefix>-web`（`app.<zone>`、`PriceClass_200`、IPv6、`redirect-to-https`、TLS 最低 `TLSv1.2_2021`；預設 behavior 到 S3 加 SPA fallback function；`/api/*` 到 API Gateway，`Managed-CachingDisabled`、`Managed-AllViewerExceptHostHeader`、`https-only`，帶 origin verify header）；CloudFront WAF `<prefix>-web`（us-east-1，`AWSManagedRulesCommonRuleSet`、`AWSManagedRulesKnownBadInputsRuleSet`、每個 IP 每 5 分鐘 2000 次，log 進 us-east-1 的 `aws-waf-logs-<prefix>-web`）；`app.<zone>` 的 A、AAAA alias record；CloudFront 標準 log v2（delivery 在 us-east-1）進 log bucket `<prefix>-cdn-logs-<account>` | dns、certificate、api |

`api` 的 route：

| route | authorizer | scope |
|---|---|---|
| `GET /api/health` | 無（`public = true`） | — |
| `GET /api/items` | `cognito` | `api/read` |
| `POST /api/items` | `cognito` | `api/write` |

`apigateway-http` 要求每條 route 寫明 authorizer 或 `public = true`（design K12），新增 route 時照這個寫法。

「讀」欄看不出來的順序限制：

- `iam` 比 `api` 先 apply，拿不到 Lambda 的 log group ARN，所以照命名規則組：function 名稱 `<prefix>-api`、log group `/aws/lambda/<prefix>-api`（`iam/naming.tf`）。改 `api` 的 function 名稱時，`iam` 要一起改；兩邊的測試各自寫死同一個期望值。
- `iam` 的 `api_role_arn` 等 policy 附加完才發布，`api` 看到 role 時權限已經在。
- `certificate` 要等上層網域的 NS 委派生效才簽得下來，委派是人工步驟（〈第一次 apply〉）。
- `api` 的映像 tag 要先存在 ECR，`api` 才 apply 得過。
- `web` 在 `api` 之後：CloudFront 的 `/api/*` origin 是 `api` 發布的 execute-api 主機名稱。

## SSM 合約

路徑 `/<project>/<env>/<stack>/<key>`（[ADR-0003](../../../docs/adr/0003-cross-stack-values-via-ssm-only.md)），只有樹 A，沒有 bridge。下表照各 stack 的 `ssm-outputs.tf` 與 `ssm-inputs.tf` 整理，不一致時以程式碼為準。

| key | 型別 | 內容 | 讀的 stack |
|---|---|---|---|
| `containerimage/api_repository_url` | String | ECR repository URL，不含 tag | `api` |
| `foundation/kms_key_arn` | String | 共用 CMK | `data`、`iam`、`api` |
| `foundation/alarm_topic_arn` | String | 告警 SNS topic | `api` |
| `foundation/api_secret_arn` | String | 第三方 API key 的 secret（完整 ARN） | `iam`、`api` |
| `foundation/origin_verify_secret_arn` | String | origin verify 值的 secret（完整 ARN） | `iam`、`api` |
| `dns/zone_id` | String | hosted zone ID | `certificate`、`web` |
| `dns/zone_name` | String | `<zone>` | `certificate`、`auth`、`web` |
| `dns/name_servers` | StringList | zone 的 4 個 name server | 沒有 stack 讀；給人做 NS 委派 |
| `certificate/web_certificate_arn` | String | `app.<zone>` 的 us-east-1 憑證 | `web` |
| `auth/issuer_url` | String | user pool 的 issuer | `api` |
| `auth/spa_client_id` | String | SPA client ID | `api`（JWT audience） |
| `auth/user_pool_arn` | String | user pool ARN | 沒有 stack 讀；給管理使用者的工具 |
| `data/table_name` | String | table 名稱 | `api` |
| `data/table_arn` | String | table ARN | `iam` |
| `iam/api_role_arn` | String | API Lambda 的 execution role | `api` |
| `api/api_endpoint` | String | execute-api 主機名稱，不含 `https://` | `web` |
| `web/site_bucket_name` | String | SPA bucket 名稱 | 沒有 stack 讀；給上傳 SPA 的流程 |
| `web/distribution_id` | String | CloudFront distribution ID | 沒有 stack 讀；給 invalidation |

跟 design §8.2 的差異：`dns/zone_name` 由 `auth` 讀（組 callback 網址），`api` 不讀 `dns`；多了 `dns/name_servers` 與 `web` 的兩個 key。

`check-ssm-contract.sh` 檢查兩件事：每個讀取的 key 都由 `ORDER` 更早的 stack 發布、型別一致；同一個 env 各 stack tfvars 的 `project`、`env`、`aws_region`、`expected_account_id` 一致，`env` 等於檔名。`api` 與 `web` 的 `origin_verify_header_name` 要一致，兩邊的測試把它釘在 `X-Origin-Verify`，改名時兩份 tfvars 與測試一起改。

## 第一次 apply

複製範本的專案第一次在自己帳號部署時照這個順序（以 `dev` 為例，在 `infra/terraform` 底下，AWS 身分自己帶）。這個 repo 只做離線驗證，不 apply。

1. 先建不依賴委派的三個 stack：

   ```bash
   ./stacks.sh dev containerimage apply
   ./stacks.sh dev foundation apply
   ./stacks.sh dev dns apply        # 輸出 4 個 name server；之後用 ./stacks.sh dev dns output 再看
   ```

2. 在上層網域 `example.com` 的 zone 加一筆 NS record：名稱 `dev.example.com`，值是上一步的 4 個 name server。上層網域不在同一個帳號或不在 Route 53 也可以，到它的 DNS 服務商加。加完確認：

   ```bash
   dig NS dev.example.com +short
   ```

   `stacks.sh` 不檢查委派，離線沒有可靠的方式判斷，這一步靠人確認。
3. 產生 origin verify 的值，寫進 secret，再從 secret 讀回來給 `web`。值不經過指令參數；用 48 個十六進位字元，放進 HTTP header 不用跳脫：

   ```bash
   secret_arn=$(aws ssm get-parameter --name /example/dev/foundation/origin_verify_secret_arn --query Parameter.Value --output text)
   openssl rand -hex 24 | tr -d '\n' \
     | aws secretsmanager put-secret-value --secret-id "$secret_arn" --secret-string file:///dev/stdin
   export TF_VAR_origin_verify_header_value="$(aws secretsmanager get-secret-value --secret-id "$secret_arn" --query SecretString --output text)"
   ```

   `web` 的變數是 `sensitive`，plan 顯示 `(sensitive value)`，但值會以明文進 `web` 的 state（design §4.1），state bucket 的權限要照機密管。第三方 API key 也在這時寫進 `foundation/api_secret_arn` 的 secret，同樣用 `file:///dev/stdin` 傳值，不放進指令參數。
4. build API 映像（arm64）並推到 `containerimage` 的 repository，tag 等於 `api/envs/dev.tfvars` 的 `api_image_tag`：

   ```bash
   repo=$(aws ssm get-parameter --name /example/dev/containerimage/api_repository_url --query Parameter.Value --output text)
   aws ecr get-login-password | docker login --username AWS --password-stdin "${repo%%/*}"
   docker build --platform linux/arm64 -t "$repo:0.1.0" <app 目錄>
   docker push "$repo:0.1.0"
   ```

5. 跑全部：

   ```bash
   ./stacks.sh dev all apply
   ```

   已經 apply 過的三個 stack 不會有變更。`certificate` 會等到憑證簽發；委派沒做或做錯，ACM 驗不到 DNS record，等滿 45 分鐘（`acm-certificate` 的 `validation_timeout`）後 timeout 失敗，錯誤訊息看得出是在等驗證，修好委派再跑一次。`web` 建 CloudFront 要幾分鐘到十幾分鐘。
6. 上傳 SPA 並清 CloudFront 快取（見〈runbook：發布 SPA 與 API 新版本〉）。

之後的 apply 不用再等憑證：已經簽發，到期前 ACM 自動續約，只要驗證 record 還在 zone 裡。

## 應用程式合約

下面是範本與 API 程式之間的約定。Terraform 與 mock 測試都檢查不到，應用程式漏做就有缺口，上線前要逐項確認。

| 約定 | 為什麼 |
|---|---|
| **每個請求（含 `GET /api/health`）都比對 origin verify header，不符就回 403。** header 名稱在環境變數 `ORIGIN_VERIFY_HEADER_NAME`（`X-Origin-Verify`），期望值從 `ORIGIN_VERIFY_SECRET_ARN` 的 secret 讀。比對用固定時間的字串比較 | execute-api 網址（`<api id>.execute-api.<region>.amazonaws.com`）是公開的，CloudFront 要用它當 origin，所以不能關。沒有這段檢查，直接打這個網址就繞過 CloudFront WAF（design §4.3、K17） |
| **同時接受 secret 的 `AWSCURRENT` 與 `AWSPREVIOUS` 兩個版本**（有 `AWSPREVIOUS` 才比對），快取最多 5 分鐘 | 換值時不中斷（〈runbook：換 origin verify 的值〉）。這是範本建議的做法，換成別的雙值機制也可以，但換值步驟要跟著改 |
| JWT 由 API Gateway 驗，Lambda 不用重驗；要用使用者身分就讀 `requestContext.authorizer.jwt.claims`（payload 格式 2.0） | `GET /api/health` 以外的 route 都要 Cognito access token 與對應的 scope（`api/read`、`api/write`）。繞過 WAF 也繞不過登入 |
| 所有 route 都在 `/api/` 底下，路徑照原樣處理 | CloudFront 只把 `/api/*` 轉給 API Gateway，路徑不改寫；其他路徑會進 S3 |
| 不要依賴 `Host` header | CloudFront 不轉送 viewer 的 Host（`AllViewerExceptHostHeader`），Lambda 看到的是 execute-api 的主機名稱。要組對外網址就用 `app.<zone>` |
| 回應不會被 CloudFront 快取 | `/api/*` 用 `Managed-CachingDisabled` |
| 讀寫 DynamoDB 用環境變數 `TABLE_NAME`；第三方 API key 從 `API_SECRET_ARN` 讀 | role 只給這張 table（含 index）與這兩個 secret |

SPA 端：用 authorization code 加 PKCE 向 `https://<domain_prefix>.auth.<region>.amazoncognito.com` 登入，client ID 是 `auth/spa_client_id`，callback 是 `https://app.<zone>/callback`（dev 另有 `http://localhost:5173/callback`），呼叫 API 用同源的 `/api/...`，不需要 CORS。

## runbook：換 origin verify 的值

CloudFront 一次只送一個值，所以要先讓 Lambda 接受新舊兩個值，再換 CloudFront，最後拿掉舊值。前提是 Lambda 照〈應用程式合約〉同時接受 `AWSCURRENT` 與 `AWSPREVIOUS`。

1. 寫入新值（`secret_arn` 的取法同〈第一次 apply〉第 3 步）。Secrets Manager 自動把舊值標成 `AWSPREVIOUS`，新值成為 `AWSCURRENT`：

   ```bash
   openssl rand -hex 24 | tr -d '\n' \
     | aws secretsmanager put-secret-value --secret-id "$secret_arn" --secret-string file:///dev/stdin
   ```

2. 等 Lambda 的快取過期（最多 5 分鐘），這時新舊值都會通過。
3. 用新值 apply `web`，等 distribution 部署完成：

   ```bash
   export TF_VAR_origin_verify_header_value="$(aws secretsmanager get-secret-value --secret-id "$secret_arn" --query SecretString --output text)"
   ./stacks.sh dev web apply
   aws cloudfront wait distribution-deployed --id "$(aws ssm get-parameter --name /example/dev/web/distribution_id --query Parameter.Value --output text)"
   ```

4. 拿掉舊值：把 `AWSPREVIOUS` 從舊版本移除，Lambda 快取過期後只接受新值。

   ```bash
   aws secretsmanager list-secret-version-ids --secret-id "$secret_arn"   # 找出 AWSPREVIOUS 的 VersionId
   aws secretsmanager update-secret-version-stage --secret-id "$secret_arn" \
     --version-stage AWSPREVIOUS --remove-from-version-id <舊版本的 VersionId>
   ```

Lambda 沒做雙值比對時，第 1 步之後到第 3 步完成之前，經 CloudFront 的 API 請求會回 403。

## runbook：發布 SPA 與 API 新版本

SPA：上傳 build 結果，再清 CloudFront 快取。bucket 沒開 versioning，`--delete` 刪掉的舊檔就沒了。

```bash
bucket=$(aws ssm get-parameter --name /example/dev/web/site_bucket_name --query Parameter.Value --output text)
dist=$(aws ssm get-parameter --name /example/dev/web/distribution_id --query Parameter.Value --output text)
aws s3 sync <SPA 的 build 目錄> "s3://$bucket/" --delete
aws cloudfront create-invalidation --distribution-id "$dist" --paths '/*'
```

路徑最後一段沒有副檔名（例如 `/orders/42`）時，viewer-request 的 CloudFront Function 會改成 `/index.html`，讓 SPA 自己處理路由；有副檔名但 bucket 裡沒有的檔案回 403（OAC 沒有 `ListBucket`，所以不是 404）。這個 function 只掛在預設 behavior，`/api/*` 的 403、404 原樣回給前端。

API：推新映像（〈第一次 apply〉第 4 步，換 tag），改 `api/envs/<env>.tfvars` 的 `api_image_tag`，apply `api`。tag 不能用 `latest`；回滾就把 tag 改回去再 apply。`containerimage` 的保留規則最多留 50 個映像，留夠可以回滾的版本。

## 執行 apply 的身分要有的權限

除了建立各資源的一般權限，下面幾項容易漏。清單依 AWS 文件整理，沒有對真實帳號核對：

| 權限 | 哪個 stack | 說明 |
|---|---|---|
| `ecr:BatchGetImage`、`ecr:GetDownloadUrlForLayer` | `api` | execution role 沒有 ECR 權限；同帳號的 Lambda 建立或更新映像時，靠執行 apply 的身分拉映像（跟 example2 相同）。沒有在真實帳號確認 |
| `iam:PassRole`（`<prefix>-api-lambda`） | `api` | 把 execution role 交給 Lambda |
| `kms:CreateGrant`、`kms:Decrypt` | `data`、`api` | DynamoDB 與 Lambda（環境變數、log group）用共用 CMK |
| `logs:CreateDelivery`、`logs:PutDeliverySource`、`logs:PutDeliveryDestination` 等 vended log 權限，含 us-east-1 | `web` | CloudFront 標準 log v2 |
| `wafv2:*` 與 `logs:*`（us-east-1） | `web` | CloudFront WAF 與它的 log group 都在 us-east-1 |
| `acm:*`（us-east-1） | `certificate` | 憑證在 us-east-1 |

## destroy

`./stacks.sh <env> all destroy` 依反向順序跑，下面幾種資源會擋住，要先處理：

| 資源 | 預設 | 要先做什麼 |
|---|---|---|
| site bucket、CloudFront log bucket（`web`） | `force_destroy = false` | 不是空的刪不掉。先清空，確認 log 不需要再刪 |
| CloudFront distribution（`web`） | Terraform 先停用再刪除 | 停用要等部署完成，`web` 的 destroy 會花十幾分鐘 |
| ACM 憑證（`certificate`） | 反向順序下 `web` 先拆 | 還被 CloudFront 用時刪不掉。distribution 剛刪掉時 ACM 可能還沒解除關聯，失敗就等幾分鐘再跑（沒有在真實帳號確認） |
| DynamoDB table（`data`） | dev 關、sit 開 deletion protection | sit 先把 `deletion_protection = false` apply 進去再 destroy。刪 table 會一起刪掉 PITR，要保留資料先做 on-demand backup 或匯出到 S3 |
| Cognito user pool（`auth`） | dev 關、sit 開 deletion protection | 同上，先 apply `deletion_protection = false`。使用者資料會一起刪掉 |
| hosted zone（`dns`） | `force_destroy = false` | zone 裡有 Terraform 以外建的 record 就刪不掉，先刪掉那些 record（`app` 的 alias 與憑證驗證 record 由 `web`、`certificate` 管，會先被刪）。上層網域的 NS 委派要自己拿掉 |
| ECR repository（`containerimage`） | `force_delete = false` | repository 裡有映像刪不掉，先清空 |
| Secrets Manager secret（`foundation`） | 刪除後保留 7 天 | 期間不能用同名重建；值在 Terraform 外寫，刪了就沒有，要先備份 |
| CMK（`foundation`） | 刪除等待 30 天 | 其他 stack 都拆完再 destroy `foundation`，不然 table 的備份與 log 解不開 |

destroy 不會刪範本以外建的東西：state bucket、上層網域的 NS record、推進 ECR 的映像（repository 清空時一起刪）、上傳到 bucket 的 SPA（bucket 清空時一起刪）。

## 複製出去之後要改什麼

| 項目 | 改什麼 |
|---|---|
| module 的 `source` | 從 HCP private registry 引用（`app.terraform.io/libterty/<module>/aws`，ADR-0004）；換 organization 或改 git 來源見 [`docs/guides/consuming-modules.md`](../../../docs/guides/consuming-modules.md) |
| 帳號表 | 9 個 stack 的 `common.tf` 的 `accounts_by_env`（`111111111111`、`222222222222`），同步改、保持一字不差 |
| state | 每份 `envs/*.tfbackend` 的 `bucket`、`kms_key_id`，`key` 的 `example-` 前綴換成自己的 `project`。state bucket 的強化做法見 [example4 REFERENCE〈前置作業的細節〉第 1 項](../../example4/infra/REFERENCE.md#前置作業的細節)；`web` 的 state 有 origin verify 的明文 |
| 每份 tfvars | `project`、`expected_account_id` |
| `foundation` | `alarm_emails`（現在是 `platform-alerts@example.com`） |
| `dns` | `domain_name`（`dev.example.com`、`sit.example.com`），換成自己網域底下的子網域 |
| `auth` | `domain_prefix`（`example-dev-login`，同一個 region 內唯一，不能含 `aws`、`amazon`、`cognito`）；`local_dev_origins`（dev 是 `http://localhost:5173`）；`deletion_protection` |
| `data` | `point_in_time_recovery_days`、`deletion_protection`；有查詢需求時在 `data/table.tf` 加 GSI（`iam` 已經放行 table 的 index） |
| `api` | `api_image_tag`、`api_reserved_concurrency`、`api_throttling`、`log_retention_days`；route 在 `api/api.tf` 的 `api_routes`，scope 要跟 `auth` 的 resource server 一致 |
| `web` | `waf_rate_limit_per_5min`（2000）、`log_retention_days`；`origin_verify_header_name` 要跟 `api` 一致 |
| `containerimage` | `lifecycle_rules` |
| 命名規則 | Lambda 名稱 `<prefix>-api` 在 `iam/naming.tf` 與 `api/function.tf` 各一份，要一起改 |

## 已知限制的細節

下面是 mock 驗不到或刻意不做的事，第一次 apply 時要逐項確認。

| 範圍 | 限制 |
|---|---|
| WAF 與繞過 | HTTP API 不能掛 WAF（AWS WAF 文件，實作時確認），WAF 只在 CloudFront。直接打 execute-api 網址會繞過 WAF，只靠 Lambda 比對 origin verify header（〈應用程式合約〉）、JWT、stage throttling 與 reserved concurrency 限制影響。`public = true` 的 route 被直接打時只剩 origin verify 檢查 |
| origin verify 的值 | 以明文存在 `web` 的 state（CloudFront 的 `custom_header.value` 不是 sensitive，design §2 第 2 點）；換值要照 runbook，靠 Lambda 的雙值比對才不中斷 |
| Cognito 寄信 | `COGNITO_DEFAULT` 每個帳號每天 50 封（Cognito quota 文件）。sit 做大量註冊或重設密碼測試會撞到；正式上線前改用 SES（`cognito-user-pool` 這一版沒有 SES 的輸入，要升 module） |
| Cognito domain | 只有 prefix domain，沒有 custom domain（design K10）；登入頁網址在 `amazoncognito.com` 底下 |
| Lambda 拉映像 | execution role 沒有 ECR 權限，靠執行 apply 的身分；Lambda 之後自己更新或擴展時是否還需要額外權限，沒有在真實帳號確認 |
| CloudFront log | delivery source 在 us-east-1、log bucket 在 ap-northeast-1，跨 region delivery 沒有在真實帳號確認。log bucket 用 SSE-S3，因為共用 CMK 的 key policy 沒有放行 `delivery.logs.amazonaws.com` |
| WAF log | log group 在 us-east-1，沒有用 CMK（共用 CMK 在 ap-northeast-1）；會遮蔽 `authorization`、`cookie` 與 origin verify header |
| SPA bucket | SSE-S3、沒有 versioning；缺檔回 403 不是 404 |
| 沒有 VPC | Lambda 不進 VPC，DynamoDB、Secrets Manager 走公網 endpoint（design K13）。要連 VPC 內的資源就要加 network stack 與 NAT 或 endpoint |
| IAM 與 KMS | `iam` 的動作清單與 `foundation` key policy 的 condition key 依文件寫，沒有對真實帳號驗證 |
| 告警門檻 | `api` 的兩個告警是起始值（5 分鐘內 ≥ 1），沒有用真實流量調過；沒有 CloudFront、WAF、DynamoDB 的告警 |

## 驗證

```bash
scripts/validate.sh templates/example6/infra/terraform
```

依序做 `fmt`、靜態規則（含 S1 mock provider、S8 stack 只呼叫 module、S10 lock 的 darwin 與 linux hash、S11 terraform-docs）、`check-ssm-contract.sh`；再對每個 stack 跑 `init -backend=false`、`validate`、`terraform test`（`dev`、`sit` 兩份 tfvars 各一次），最後 tflint。全部離線，不需要 AWS 憑證，但需要 HCP registry token。

### 靜態驗證通過（2026-10-28）

| 項目 | 結果 |
|---|---|
| `scripts/validate.sh templates/example6/infra/terraform` 全量 | 通過：fmt、靜態規則（含 S10、S11）、9 個 stack 的 `init -backend=false`、`validate`、tflint |
| `terraform test` | 9 個 stack、27 個測試檔、200 個 run 全過（每個 stack 的主測試加 `dev`、`sit` 兩份 tfvars 測試） |
| `check-ssm-contract.sh` | 9 個 stack、21 個讀取、2 個 env 通過 |
| `stacks.sh dev all plan --dry-run` | 依 ORDER 印出 9 個 stack 的指令，`destroy` 反向 |

### 雲端整合待驗證

需要真實帳號，這個里程碑沒有做。

| 項目 | 怎麼確認 |
|---|---|
| DNS 委派與憑證 | 委派後 `certificate` 在 45 分鐘內簽發；`app.<zone>` 的 A、AAAA 解析到 CloudFront |
| CloudFront 到 S3 | OAC 讀得到 SSE-S3 的物件；bucket policy 只放行這個 distribution；SPA fallback 只作用在預設 behavior |
| CloudFront 到 API Gateway | `AllViewerExceptHostHeader` 下 execute-api 正常回應；`Authorization` header 有轉送；origin verify header 送到 Lambda |
| 繞過 WAF | 直接打 execute-api 網址、不帶 header 時回 403（取決於應用程式）；帶錯的值也回 403 |
| JWT | Cognito access token 的 `client_id` 與 audience 設定相符、scope 檢查生效；`GET /api/health` 不需要 token |
| origin verify 換值 | 照 runbook 換值期間沒有 403 |
| Lambda | 執行 apply 的身分拉得到 ECR 映像；讀得到 CMK 加密的 secret 與 table；log 寫進 CMK 加密的 log group |
| HTTP API access log | 不需要帳號層的 CloudWatch role 就寫得進 CMK 加密的 log group |
| CloudFront log | us-east-1 的 delivery 寫得進 ap-northeast-1 的 bucket |
| WAF | managed rules 與 rate limit 生效；log 遮蔽 origin verify header |
| Cognito | `COGNITO_DEFAULT` 寄得出驗證信；prefix domain 的登入頁、PKCE 流程、callback 與 logout 網址 |
| 告警 | Lambda `Errors`、API `5xx` 的 dimension 對得上指標，送到 CMK 加密的 SNS topic |
| destroy | 憑證在 distribution 刪除後多久可以刪；sit 關掉 deletion protection 後 `data`、`auth` 拆得掉 |
