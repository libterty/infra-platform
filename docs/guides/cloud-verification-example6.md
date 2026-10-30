# example6 雲端驗證 runbook

## 結論

這份 runbook 列出 `templates/example6` 第一次在真實 AWS 帳號 apply 時要逐項確認的事，照做完就能把 REFERENCE〈雲端整合待驗證〉表與 design v9 §11 的「未確認」改成有證據的結論。

- 範圍：REFERENCE 表上的 13 項（本文第 1–13 項）。design §11、§14 跟 example6 有關的點都落在這 13 項裡，對照見〈範圍〉。example2 接 CDN 的部分不在本文。
- 每一項都有：前提（要 apply 哪些 stack、tfvars 怎麼設）、指令、預期結果、結果紀錄。
- 指令預設都是唯讀。會改變狀態的指令標【寫入】，只在 `dev` 執行。
- 這份文件的指令都**沒有實際跑過**，名稱與數值都從程式碼推出來，出處寫在每段的「名稱怎麼來的」。標「推測」的是 repo 以外的慣例（AWS 的固定值、預設路徑或錯誤訊息），執行時以實際輸出為準。
- 範本沒有附 API 的程式。第 3–7 項有一半是在驗應用程式有沒有照 REFERENCE〈應用程式合約〉做；映像沒做 origin verify 比對時，第 4 項一定不通過，而且這是安全缺口，不是可以先放著的瑕疵。
- 從程式碼就看得出來、第一次驗證很可能不通過的兩件事，先講：
  1. **Lambda 帳號的並行上限**：`api` 給 reserved concurrency dev 10、sit 50（`api/envs/dev.tfvars:7`、`sit.tfvars:7`）。AWS 要求帳號保留一定數量的未保留並行（推測：至少 100），新帳號的總上限有時很低（推測：可能只有 10），這時 `api` apply 會失敗。階段 0 先用 `aws lambda get-account-settings` 看。
  2. **`Authorization` header 經 CloudFront 能不能到 API Gateway**：`/api/*` 用 `Managed-CachingDisabled` 加 `Managed-AllViewerExceptHostHeader`（`web/distribution.tf:22`、`:24`）。CloudFront 對 `Authorization` 有特別規則（推測：GET、HEAD 請求要把它放進 cache policy 才會轉送，而 `Managed-CachingDisabled` 的 cache key 不含任何 header）。如果成立，`GET /api/items` 經 CloudFront 會回 401，直接打 execute-api 帶同一個 token 卻是 200。第 5 項會直接比對這兩個結果。

## 範圍

涵蓋：

| 編號 | 項目 | 來源 |
|---|---|---|
| 1–13 | DNS 委派與憑證、CloudFront 到 S3、CloudFront 到 API Gateway、繞過 WAF、JWT、origin verify 換值、Lambda、HTTP API access log、CloudFront log、WAF、Cognito、告警、destroy | `templates/example6/infra/REFERENCE.md:282-296`〈雲端整合待驗證〉 |

design §11、§14 各點的去處：

| design | 內容 | 在本文 |
|---|---|---|
| §11 第 1 點 | origin verify 換值會中斷（`alb` module） | 不在本文：example2。example6 的換值靠 Lambda 雙值比對，在第 6 項 |
| §11 第 2 點、§4.3 | 直接打 execute-api 繞過 WAF，靠 Lambda 的 origin verify 檢查 | 第 4 項 |
| §11 第 3 點 | K8 的 Host 與 SNI（ALB 憑證） | 不在本文：example2。example6 對應的是不轉送 Host，在第 3 項 |
| §11 第 4、5 點 | ALB WAF 的 rate limit、ALB SG 的 prefix list 配額 | 不在本文：example2 |
| §11 第 6 點、§2 第 5 點 | DNS 委派是 `dns` 與 `certificate` 之間的人工步驟 | 第 1 項 |
| §11 第 7 點、K11、§14 | `COGNITO_DEFAULT` 每天 50 封 | 第 11 項 |
| §11 第 8 點、§5.6、§14 | HTTP API access log 不需要帳號層的 CloudWatch role | 第 8 項 |
| §11 第 9 點 | `moved` 搬 for_each resource | 不在本文：project-infra 的 secret 搬遷，跟 example6 無關 |
| §11 第 10 點、§2 第 7 點 | CloudFront log 從 us-east-1 跨 region 送到 ap-northeast-1 的 bucket | 第 9 項 |
| §11 第 11 點 | destroy 會被擋的資源 | 第 13 項 |
| §2 第 6 點、§14 | HTTP API 不能掛 WAF | 不另驗：§14 已用 AWS 文件確認；第 4 項確認繞過時的實際行為 |
| §8.1 | `web` 的 bucket policy 與 distribution 不形成循環 | 不在本文：I9 已用 `terraform validate` 離線確認；階段 D 的 apply 成功就是雲端的證據 |
| §14 範本 | Lambda 拉 ECR 映像靠部署身分，execution role 沒有 ECR 權限 | 第 7 項 |

不涵蓋：REFERENCE〈已知限制的細節〉裡刻意不做的事（custom domain、SES、VPC、CloudFront 與 DynamoDB 的告警），以及告警門檻的調校（要真實流量，不是一次性的驗證）。

## 需要的權限與工具

工具：

- AWS CLI v2、`jq` 1.7 以上（第 5 項用 `@base64d` 解沒有補齊 `=` 的 JWT）、`curl`、`dig`、`openssl`、Terraform（apply 用）。
- `docker` 與 `buildx`，build arm64 映像（REFERENCE〈第一次 apply〉第 4 步）。
- 一個瀏覽器：第 5、11 項要在 hosted UI 登入。
- 一個收得到信的 email 信箱：SNS 訂閱確認、第 11 項的邀請信。下面寫成 `<test-email>`。

身分：

| 用途 | 身分 | 依據 |
|---|---|---|
| apply 9 個 stack | 各 stack 的 apply 身分；要有 REFERENCE〈執行 apply 的身分要有的權限〉列的項目，含 `ecr:BatchGetImage`、`ecr:GetDownloadUrlForLayer` 與 us-east-1 的 `acm:*`、`wafv2:*`、`logs:*` | `REFERENCE.md:195-206` |
| 執行本文的唯讀指令 | 驗證身分（權限見下面） | 無 |
| 第 5、11 項登入 | Cognito 的測試使用者（第 11 項建立） | 無 |

驗證身分要的 AWS 權限（唯讀）：`ssm:GetParameter`、`route53:GetHostedZone`、`route53:ListResourceRecordSets`、`route53:ListHostedZonesByName`、`acm:DescribeCertificate`、`acm:ListCertificates`、`cloudfront:GetDistribution`、`cloudfront:ListDistributions`、`cloudfront:GetCachePolicy`、`cloudfront:GetOriginRequestPolicy`、`cloudfront:ListOriginAccessControls`、`s3:GetBucketPolicy`、`s3:GetEncryptionConfiguration`、`s3:GetBucketLocation`、`s3:ListBucket`、`apigateway:GET`、`lambda:GetFunction`、`lambda:GetFunctionConcurrency`、`lambda:GetPolicy`、`lambda:GetAccountSettings`、`ecr:DescribeImages`、`ecr:GetRepositoryPolicy`、`dynamodb:DescribeTable`、`dynamodb:DescribeContinuousBackups`、`dynamodb:Scan`（只用 `--select COUNT`）、`logs:Describe*`、`logs:FilterLogEvents`、`wafv2:GetWebACL`、`wafv2:GetLoggingConfiguration`、`cognito-idp:DescribeUserPool`、`cognito-idp:DescribeUserPoolClient`、`cognito-idp:DescribeUserPoolDomain`、`cognito-idp:DescribeResourceServer`、`cloudwatch:DescribeAlarms`、`cloudwatch:ListMetrics`、`sns:GetTopicAttributes`、`sns:ListSubscriptionsByTopic`、`secretsmanager:DescribeSecret`、`secretsmanager:ListSecretVersionIds`、`kms:DescribeKey`、`iam:GetRole`、`iam:ListRolePolicies`、`iam:ListAttachedRolePolicies`、`cloudtrail:LookupEvents`。

第 4、5、6 項要讀 origin verify 的值：`secretsmanager:GetSecretValue` 加共用 CMK 的 `kms:Decrypt`。值只經 pipe 交給 `curl -H @-`，不放進指令參數，也不要印出來。

【寫入】要另外的權限：`s3:PutObject`、`s3:DeleteObject`（上傳測試檔、destroy 前清空 bucket）、`cloudfront:CreateInvalidation`、`secretsmanager:PutSecretValue`、`secretsmanager:UpdateSecretVersionStage`、`cognito-idp:AdminCreateUser`、`cognito-idp:AdminDeleteUser`、`cloudwatch:SetAlarmState`、`lambda:PutFunctionConcurrency`、`ecr:BatchDeleteImage`。

網路：沒有 VPC，所有指令都能在任何連得到網際網路的地方跑。第 10 項的 rate limit 測試會讓 WAF 擋掉你的來源 IP 幾分鐘，放在最後做，或換一個 IP。

## 共用變數

每次開新的 shell 先跑這段。`<project>`、`<env>` 換成 tfvars 的值（`dev` 或 `sit`）。要在階段 D 之後才拿得到全部的值；階段 A、B 只會有 `dns` 以前的。

```bash
export AWS_REGION=ap-northeast-1          # common.tf:24，aws_region 預設值；改過就跟著改
P=<project>                               # tfvars 的 project
E=<env>                                   # dev 或 sit
ssm() { aws ssm get-parameter --name "$1" --query Parameter.Value --output text; }
hc()  { curl -s -o /dev/null -w '%{http_code} %{content_type} %{redirect_url}\n' "$@"; }
since() { echo $(( ($(date +%s) - $1) * 1000 )); }   # since 900 = 15 分鐘前，給 --start-time 用

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
PREFIX="$P-$E"
ZONE=$(ssm "/$P/$E/dns/zone_name")                    # 例如 dev.example.com
ZONE_ID=$(ssm "/$P/$E/dns/zone_id")
APP="app.$ZONE"
CERT_ARN=$(ssm "/$P/$E/certificate/web_certificate_arn")
ISSUER=$(ssm "/$P/$E/auth/issuer_url")
POOL_ID=${ISSUER##*/}
CLIENT_ID=$(ssm "/$P/$E/auth/spa_client_id")
COGNITO_DOMAIN="$(aws cognito-idp describe-user-pool --user-pool-id "$POOL_ID" --query UserPool.Domain --output text).auth.$AWS_REGION.amazoncognito.com"
TABLE=$(ssm "/$P/$E/data/table_name")
API_HOST=$(ssm "/$P/$E/api/api_endpoint")            # <api id>.execute-api.<region>.amazonaws.com
API_ID=${API_HOST%%.*}
BUCKET=$(ssm "/$P/$E/web/site_bucket_name")
LOG_BUCKET="$PREFIX-cdn-logs-$ACCOUNT"
DIST=$(ssm "/$P/$E/web/distribution_id")
KMS_ARN=$(ssm "/$P/$E/foundation/kms_key_arn")
TOPIC=$(ssm "/$P/$E/foundation/alarm_topic_arn")
OV_SECRET=$(ssm "/$P/$E/foundation/origin_verify_secret_arn")
HDR=X-Origin-Verify                       # api/envs/<env>.tfvars:13、web/envs/<env>.tfvars:8

# origin verify 的值只經 pipe 交給 curl，不進指令參數：ov_header [AWSCURRENT|AWSPREVIOUS]
ov_header() {
  aws secretsmanager get-secret-value --secret-id "$OV_SECRET" --version-stage "${1:-AWSCURRENT}" \
    --query SecretString --output text | sed "s/^/$HDR: /"
}
```

名稱怎麼來的：

- `<project>-<env>`：`common.tf:44` 的 `name_prefix = "${var.project}-${var.env}"`。9 個 stack 的 `common.tf` 一字不差。
- SSM 路徑：`common.tf:45` 的 `ssm_prefix = "/${var.project}/${var.env}"`，加 `modules/ssm-publish/main.tf:4` 的 `"${var.ssm_prefix}/${var.stack}/${each.key}"`；key 名稱見各 stack 的 `ssm-outputs.tf`（`dns/ssm-outputs.tf:3-8`、`certificate/ssm-outputs.tf:3`、`auth/ssm-outputs.tf:3-5`、`data/ssm-outputs.tf:3-4`、`api/ssm-outputs.tf:4`、`web/ssm-outputs.tf:4-5`、`foundation/ssm-outputs.tf:3-6`）。
- `api_endpoint` 是去掉 `https://` 的主機名稱（`api/ssm-outputs.tf:4`），第一段是 API ID（`modules/apigateway-http/outputs.tf:7` 的格式說明）。
- `POOL_ID` 取 issuer 的最後一段：`modules/cognito-user-pool/outputs.tf:13` 的 `https://cognito-idp.<region>.amazonaws.com/<pool id>`。
- hosted UI 網域：`modules/cognito-user-pool/outputs.tf:23`；`domain_prefix` 在 `auth/envs/<env>.tfvars:6`。
- log bucket：`web/buckets.tf:14` 的 `"${local.name_prefix}-cdn-logs-${var.expected_account_id}"`；`expected_account_id` 等於實際帳號（`providers.tf:14` 的 `allowed_account_ids`）。

## 執行順序

順序照 `stacks.sh:8` 的 `ORDER` 與 REFERENCE〈第一次 apply〉（`REFERENCE.md:85-132`）。每個 stack 第一次用之前要先 `./stacks.sh <env> <stack> init`（`stacks.sh:119`；README 與 REFERENCE 的步驟沒寫這步）。每個指令先跑一次 `--dry-run` 看要執行什麼。

| 階段 | 做什麼 | 做完接著驗 |
|---|---|---|
| 0 | 照 README〈複製出去之後要改什麼〉換掉佔位值；`foundation` 的 `alarm_emails` 換成會收信的地址；9 個 stack 各跑一次 `init`；`aws lambda get-account-settings` 確認並行上限（〈結論〉第 1 點）；準備照〈應用程式合約〉實作的 API 映像 | 無 |
| A | `./stacks.sh <env> containerimage apply`、`foundation apply`、`dns apply` | 點 SNS 訂閱確認信 |
| B | 上層網域加 NS 委派（人工，REFERENCE〈第一次 apply〉第 2 步） | 第 1 項前半 |
| C | 寫入 origin verify 與第三方 API key 的值、`export TF_VAR_origin_verify_header_value`、推 arm64 映像（REFERENCE〈第一次 apply〉第 3、4 步） | 無 |
| D | `./stacks.sh <env> all apply`；記下 `certificate` 開始與結束的時間 | 第 1 項後半；第 7、8、9、12 項的設定部分 |
| E | 上傳 SPA（或第 2 項的測試檔）並 invalidation | 第 2、3 項 |
| F | 建測試使用者並登入 | 第 11、5、4 項，第 7 項的讀寫部分 |
| G | WAF 規則測試；rate limit 放最後 | 第 10 項；隔 10 分鐘看第 8、9 項的 log |
| H | 換 origin verify 的值 | 第 6 項 |
| I | 告警的通知與真實觸發 | 第 12 項 |
| J | destroy（只在 dev） | 第 13 項 |

---

## 1. DNS 委派與憑證

**前提**

- 階段 A 完成，`dns` 建好 zone（`dns/zone.tf:8`，名稱是 `dns/envs/<env>.tfvars:6` 的 `domain_name`）。
- 階段 B：在上層網域加一筆 NS record，名稱是 zone 名稱，值是 `dns` 輸出的 4 個 name server。
- 階段 D 跑到 `certificate` 時，記下開始時間。等待上限是 `acm-certificate` 的 `validation_timeout` 預設 45 分鐘（`modules/acm-certificate/variables.tf:73`、`main.tf:46-48`），`certificate` 沒有覆寫。

**指令**

階段 B 之後（`ZONE`、`ZONE_ID` 已經有值）：

```bash
aws route53 get-hosted-zone --id "$ZONE_ID" --query 'DelegationSet.NameServers' --output text
ssm "/$P/$E/dns/name_servers"              # StringList，逗號分隔
dig NS "$ZONE" +short                      # 用一般 resolver 查
dig +trace NS "$ZONE" | tail -12           # 從根往下追，看上層網域交出的 NS
```

階段 D 之後：

```bash
aws acm describe-certificate --region us-east-1 --certificate-arn "$CERT_ARN" \
  --query 'Certificate.{status:Status,name:DomainName,sans:SubjectAlternativeNames,algo:KeyAlgorithm,created:CreatedAt,issued:IssuedAt,renewal:RenewalEligibility,validation:DomainValidationOptions[].[ValidationStatus,ResourceRecord.Name]}'
aws acm list-tags-for-certificate --region us-east-1 --certificate-arn "$CERT_ARN" --output text

# 驗證 record（CNAME）
aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" \
  --query "ResourceRecordSets[?Type=='CNAME'].[Name,TTL,ResourceRecords[0].Value]" --output text

# app 的 A、AAAA alias 指到這個 distribution
aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" \
  --query "ResourceRecordSets[?Name=='$APP.'].[Type,AliasTarget.DNSName,AliasTarget.HostedZoneId]" --output text
aws cloudfront get-distribution --id "$DIST" --query 'Distribution.DomainName' --output text
dig A "$APP" +short
dig AAAA "$APP" +short
```

名稱怎麼來的：憑證名稱 `"app.${zone_name}"`、region `us-east-1`、tag `Name = "<project>-<env>-web"`（`certificate/certificates.tf:5`、`:7`、`:9`）；驗證 record 的 TTL 60、`allow_overwrite`（`modules/acm-certificate/main.tf:34`、`:38`）；`app` 的 A、AAAA alias（`web/distribution.tf:55-61`）。CloudFront alias 的 hosted zone ID 固定是 `Z2FDTNDATAQYW2`（AWS 的固定值，推測）。

**預期結果**

- 三個來源的 name server 一樣，都是 4 個；`dig +trace` 的最後幾行顯示上層網域交出這 4 個 NS。
- 憑證 `ISSUED`，名稱 `app.<zone>`，沒有 SAN，`RSA_2048`；`IssuedAt` 減 `CreatedAt` 在 45 分鐘內（記下實際分鐘數）；tag 有 `Name = <project>-<env>-web`。
- zone 裡有一筆驗證用 CNAME，TTL 60。
- `app.<zone>.` 有 A 與 AAAA 兩筆，`AliasTarget.DNSName` 是 distribution 的網域加 `.`；`dig` 兩個都回位址。
- 如果在委派生效前就跑了 `certificate`：等滿 45 分鐘後失敗，記下錯誤訊息，確認看得出是在等驗證（REFERENCE〈第一次 apply〉第 5 步的說法）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／簽發花了幾分鐘 ______

## 2. CloudFront 到 S3

**前提**

- 階段 D 完成。site bucket 用 SSE-S3、不過期，只讓這個 distribution 經 OAC 讀（`web/buckets.tf:4-9`）。
- 階段 E：SPA 還沒好時，【寫入】上傳兩個測試檔：

  ```bash
  D=$(mktemp -d)
  printf '<!doctype html><title>runbook</title><p>runbook index</p>\n' > "$D/index.html"
  printf 'console.log("runbook");\n' > "$D/app.js"
  aws s3 cp "$D/index.html" "s3://$BUCKET/index.html"
  aws s3 cp "$D/app.js" "s3://$BUCKET/app.js"
  aws cloudfront create-invalidation --distribution-id "$DIST" --paths '/*'
  ```

**指令**

```bash
aws s3api get-bucket-encryption --bucket "$BUCKET" \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault'
aws s3api get-bucket-policy --bucket "$BUCKET" --query Policy --output text \
  | jq '.Statement[] | {Sid, Principal, Action, Condition}'

aws cloudfront get-distribution --id "$DIST" --query 'Distribution.DistributionConfig.{
  origins: Origins.Items[].{id: Id, domain: DomainName, oac: OriginAccessControlId},
  default: DefaultCacheBehavior.{origin: TargetOriginId, viewer: ViewerProtocolPolicy, fn: FunctionAssociations.Items[].[EventType, FunctionARN]},
  ordered: CacheBehaviors.Items[].{path: PathPattern, origin: TargetOriginId, fn: FunctionAssociations.Quantity},
  root: DefaultRootObject, aliases: Aliases.Items, tls: ViewerCertificate.MinimumProtocolVersion, price: PriceClass, ipv6: IsIPV6Enabled}'
aws cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[?Name=='$PREFIX-web-site']"

hc "https://$APP/"
hc "https://$APP/app.js"
hc "https://$APP/orders/42"                 # SPA fallback：應該拿到 index.html
curl -s "https://$APP/orders/42" | head -3
hc "https://$APP/missing.js"                # 有副檔名、不存在
hc "https://$APP/api/does-not-exist"        # /api/* 不套 fallback
hc "http://$APP/"                           # 轉 HTTPS
hc "https://$BUCKET.s3.$AWS_REGION.amazonaws.com/index.html"   # 直接打 bucket
curl -sI "https://$APP/" | grep -iE 'strict-transport-security|x-content-type-options|x-frame-options|x-cache'
```

名稱怎麼來的：bucket 名稱 `"${local.name_prefix}-web-${var.expected_account_id}"`（`web/buckets.tf:5`）；OAC 名稱 `"${var.name}-${each.key}"`（`modules/cloudfront-distribution/main.tf:37`），`name` 是 `<project>-<env>-web`、origin key 是 `site`（`web/distribution.tf:7`、`:13`）；fallback function `<name>-spa-fallback`（`modules/cloudfront-distribution/main.tf:47`），只掛預設 behavior（`main.tf:107-113`），邏輯在 `modules/cloudfront-distribution/functions/spa-fallback.js:3-9`；bucket policy 的 `DenyInsecureTransport` 與 `AllowCloudFrontRead`（`modules/s3-bucket/main.tf:7-14`、`:164-171`）；預設 behavior 的 response headers policy 是 `Managed-SecurityHeadersPolicy`（`modules/cloudfront-distribution/variables.tf:153`）。

**預期結果**

- bucket 加密是 `AES256`，沒有 `KMSMasterKeyID`。
- bucket policy 剛好兩條：`DenyInsecureTransport`；`AllowCloudFrontRead` 的 principal 是 `cloudfront.amazonaws.com`、action `s3:GetObject`、條件 `AWS:SourceArn` 只有這個 distribution 的 ARN。
- origin `site` 指向 `<bucket>.s3.<region>.amazonaws.com` 並帶 OAC ID；OAC `<project>-<env>-web-site` 存在（`sigv4`、`always`）。
- 預設 behavior 的 `fn` 有一個 `viewer-request` 的 `<project>-<env>-web-spa-fallback`；`/api/*` 的 `fn` 數量是 0。`root` 是 `index.html`、`aliases` 是 `app.<zone>`、`tls` 是 `TLSv1.2_2021`、`price` 是 `PriceClass_200`、`ipv6` 是 `true`。
- `/`、`/app.js`、`/orders/42` 都是 `200`，`/orders/42` 的內容是 index.html。
- `/missing.js` 是 `403`（OAC 沒有 `ListBucket`，REFERENCE〈runbook：發布 SPA 與 API 新版本〉）。
- `/api/does-not-exist` 是 API Gateway 的 `404`（`application/json`），不是 index.html 加 `200`。
- `http://` 回 `301`，`redirect_url` 是 `https://`。
- 直接打 bucket 是 `403`。
- 回應 header 有 `strict-transport-security`、`x-content-type-options`、`x-frame-options`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 3. CloudFront 到 API Gateway

**前提**

- 階段 D、E 完成；API 映像照〈應用程式合約〉實作，`GET /api/health` 在 origin verify header 正確時回 `200`。
- `/api/*` behavior：`allowed_methods = "all"`、`Managed-CachingDisabled`、`Managed-AllViewerExceptHostHeader`（`web/distribution.tf:17-26`）；origin `api` 是 `custom`，固定 `https-only`、`TLSv1.2`（`modules/cloudfront-distribution/main.tf:72-82`），帶 origin verify header（`web/distribution.tf:28`、`modules/cloudfront-distribution/main.tf:86-92`）。

**指令**

```bash
# origin：只印 header 名稱，不印值（get-distribution-config 會回明文）
aws cloudfront get-distribution --id "$DIST" --query 'Distribution.DistributionConfig.Origins.Items[?Id==`api`].{
  domain: DomainName, proto: CustomOriginConfig.OriginProtocolPolicy, ssl: CustomOriginConfig.OriginSslProtocols.Items,
  readTimeout: CustomOriginConfig.OriginReadTimeout, headers: CustomHeaders.Items[].HeaderName}'
echo "$API_HOST"

B=$(aws cloudfront get-distribution --id "$DIST" --query 'Distribution.DistributionConfig.CacheBehaviors.Items[?PathPattern==`/api/*`]|[0]' --output json)
jq '{methods: .AllowedMethods.Items, viewer: .ViewerProtocolPolicy}' <<<"$B"
aws cloudfront get-cache-policy --id "$(jq -r .CachePolicyId <<<"$B")" --query 'CachePolicy.CachePolicyConfig.Name' --output text
aws cloudfront get-origin-request-policy --id "$(jq -r .OriginRequestPolicyId <<<"$B")" \
  --query 'OriginRequestPolicy.OriginRequestPolicyConfig.{name: Name, headers: HeadersConfig}'

curl -s -w '\n%{http_code}\n' "https://$APP/api/health"
curl -s -w '\n%{http_code}\n' -X POST -H 'Content-Type: application/json' -d '{}' "https://$APP/api/items"   # 沒有 token

# 經 CloudFront 的請求在 access log 裡的樣子（log 要幾分鐘才進來）
aws logs filter-log-events --log-group-name "/aws/apigateway/$PREFIX-api-access" --start-time "$(since 900)" \
  --filter-pattern '{ $.path = "/api/health" }' --limit 5 --output json \
  | jq -r '.events[].message | fromjson | [.domainName, .ip, .userAgent, .status] | @tsv'
```

`Authorization` header 有沒有轉送，在第 5 項用真的 token 比對（〈結論〉第 2 點）。

名稱怎麼來的：origin key `api`、`domain_name` 是 SSM 的 `api/api_endpoint`（`web/distribution.tf:14`）；access log group `/aws/apigateway/<project>-<env>-api-access`（`api/api.tf:28`）；access log 欄位 `domainName`、`ip`、`userAgent`、`status`（`modules/apigateway-http/main.tf:5-22`）；read timeout 預設 30 秒（`modules/cloudfront-distribution/main.tf:14`）。origin request policy 的 `HeaderBehavior` 實際字串（例如 `allExcept`）是 CloudFront 的命名，推測。

**預期結果**

- origin `api` 的 domain 等於 `$API_HOST`，`https-only`、`TLSv1.2`、read timeout 30，`headers` 只有 `X-Origin-Verify`。
- `/api/*` 的 methods 是 7 種（GET、HEAD、OPTIONS、PUT、POST、PATCH、DELETE），`redirect-to-https`；cache policy 名稱 `Managed-CachingDisabled`；origin request policy 名稱 `Managed-AllViewerExceptHostHeader`，header 設定是「全部 viewer header，排除 `Host`」。
- `GET /api/health` 經 CloudFront 是 `200`（證明 execute-api 收得到不帶 viewer Host 的請求，Lambda 也收到正確的 origin verify header；對照第 4 項不帶 header 直接打是 `403`）。
- `POST /api/items` 沒有 token 是 `401`（API Gateway 擋，不進 Lambda）。
- access log 的 `domainName` 是 `$API_HOST`，不是 `app.<zone>`；記下 `ip` 是 viewer 的 IP 還是 CloudFront edge 的 IP。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 4. 繞過 WAF

**前提**

- 第 3 項通過。
- 這一項驗的是應用程式：Lambda 對每個請求（含 `GET /api/health`）比對 `ORIGIN_VERIFY_HEADER_NAME` 的 header 與 `ORIGIN_VERIFY_SECRET_ARN` 的值，不符回 `403`（`api/function.tf:13-20`、REFERENCE〈應用程式合約〉第一列）。
- HTTP API 保留 execute-api 網址（`api/api.tf:24`），所以直接打一定到得了 API Gateway。

**指令**

```bash
aws apigatewayv2 get-api --api-id "$API_ID" --query '{endpoint: ApiEndpoint, disabled: DisableExecuteApiEndpoint}'

hc "https://$API_HOST/api/health"                                          # 不帶 header
hc -H "$HDR: runbook-wrong-value-0000" "https://$API_HOST/api/health"        # 帶錯的值
ov_header | hc -H @- "https://$API_HOST/api/health"                          # 帶正確的值
hc "https://$API_HOST/api/items"                                           # 不帶 token
ov_header | hc -H @- "https://$API_HOST/api/items"                           # 有 header、沒有 token

# 被直接打時的成本上限
aws apigatewayv2 get-stage --api-id "$API_ID" --stage-name '$default' \
  --query '{throttle: DefaultRouteSettings, autoDeploy: AutoDeploy, accessLog: AccessLogSettings.DestinationArn}'
aws lambda get-function-concurrency --function-name "$PREFIX-api"
```

【寫入】（選做，只在 dev）確認 throttling 真的生效。直接打 execute-api 帶正確 header，送超過 burst 的請求：

```bash
H="$(mktemp -d)/h"; ov_header > "$H"      # header 檔只留在本機暫存目錄，做完刪掉
seq 1 400 | xargs -P 50 -I{} curl -s -o /dev/null -w '%{http_code}\n' -H @"$H" "https://$API_HOST/api/health" | sort | uniq -c
rm -f "$H"
```

名稱怎麼來的：Lambda 名稱 `<project>-<env>-api`（`api/function.tf:6`）；throttling 來自 `api/envs/<env>.tfvars:8-11`，設在 `$default` stage（`modules/apigateway-http/main.tf:82-90`）；reserved concurrency 來自 `api/envs/<env>.tfvars:7`（`api/function.tf:12`）；`GET /api/health` 是唯一的 public route（`api/api.tf:7`）。

**預期結果**

- `disabled` 是 `false`。
- 不帶 header：`403`。帶錯的值：`403`。帶正確的值：`200`（證明前兩個 `403` 是 header 造成的，不是別的問題）。
- `/api/items` 不帶 token：`401`；有 header、沒有 token 也是 `401`（JWT 在 Lambda 之前就擋了）。
- stage 的 throttling 等於 tfvars（dev 50／100、sit 200／400），`autoDeploy` 是 `true`，access log 指到第 8 項的 log group；reserved concurrency 等於 tfvars。
- 選做的壓測：出現 `429`（API Gateway 的 throttling），記下比例。
- **不帶 header 回 `200` 就是不通過**，而且是安全缺口：execute-api 網址繞過 WAF。修好映像之前不要對外開放。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／四個狀態碼 ______

## 5. JWT

**前提**

- 第 11 項已經建好測試使用者，而且第一次登入改過密碼。
- JWT authorizer `cognito`：issuer 是 user pool、audience 是 SPA client（`api/api.tf:17-22`），token 從 `Authorization` header 取（`modules/apigateway-http/main.tf:51`）。Cognito 的 access token 沒有 `aud`，API Gateway 改比對 `client_id`（`modules/cognito-user-pool/README.md:56`）。
- route 與 scope：`GET /api/items` 要 `api/read`、`POST /api/items` 要 `api/write`（`api/api.tf:8-9`）。

**指令**

設定面：

```bash
aws cognito-idp describe-user-pool-client --user-pool-id "$POOL_ID" --client-id "$CLIENT_ID" \
  --query 'UserPoolClient.{name: ClientName, secret: ClientSecret, flows: AllowedOAuthFlows, scopes: AllowedOAuthScopes,
           callbacks: CallbackURLs, logouts: LogoutURLs, authFlows: ExplicitAuthFlows, revocation: EnableTokenRevocation}'
aws apigatewayv2 get-authorizers --api-id "$API_ID" \
  --query 'Items[].{name: Name, type: AuthorizerType, src: IdentitySource, iss: JwtConfiguration.Issuer, aud: JwtConfiguration.Audience}'
aws apigatewayv2 get-routes --api-id "$API_ID" \
  --query 'Items[].[RouteKey, AuthorizationType, join(`,`, AuthorizationScopes || `[]`)]' --output table
```

用 authorization code 加 PKCE 拿 token（hosted UI 的 `/oauth2/authorize`、`/oauth2/token` 是 Cognito 的固定路徑，推測）：

```bash
VERIFIER=$(openssl rand -base64 48 | tr -d '\n=+/' | cut -c1-64)
CHALLENGE=$(printf '%s' "$VERIFIER" | openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')
REDIRECT="https://$APP/callback"
SCOPE="openid email api/read api/write"
enc() { jq -rn --arg v "$1" '$v|@uri'; }
echo "https://$COGNITO_DOMAIN/oauth2/authorize?response_type=code&client_id=$CLIENT_ID&redirect_uri=$(enc "$REDIRECT")&scope=$(enc "$SCOPE")&code_challenge=$CHALLENGE&code_challenge_method=S256"
# 用瀏覽器開這個網址並登入。之後網址列會是 https://app.<zone>/callback?code=...（SPA 沒有 /callback 也沒關係，code 在網址列）
CODE=<網址列的 code>
TOKENS=$(curl -s -X POST "https://$COGNITO_DOMAIN/oauth2/token" -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode grant_type=authorization_code --data-urlencode client_id="$CLIENT_ID" --data-urlencode code="$CODE" \
  --data-urlencode redirect_uri="$REDIRECT" --data-urlencode code_verifier="$VERIFIER")
AT=$(jq -r .access_token <<<"$TOKENS")
IDT=$(jq -r .id_token <<<"$TOKENS")
claims() { jq -R 'split(".")[1] | gsub("-";"+") | gsub("_";"/") | @base64d | fromjson | {iss, client_id, aud, token_use, scope, exp}' <<<"$1"; }
claims "$AT"
claims "$IDT"
```

呼叫 API：

```bash
hc "https://$APP/api/items"                                               # 沒有 token
hc -H "Authorization: Bearer $AT" "https://$APP/api/items"                # 經 CloudFront
ov_header | hc -H @- -H "Authorization: Bearer $AT" "https://$API_HOST/api/items"   # 直接打，同一個 token
hc -X POST -H "Authorization: Bearer $AT" -H 'Content-Type: application/json' -d '{"runbook":true}' "https://$APP/api/items"
hc -H "Authorization: Bearer $IDT" "https://$APP/api/items"               # id token 沒有 scope
hc -H "Authorization: Bearer ${AT%?}x" "https://$APP/api/items"           # 改壞簽章
hc "https://$APP/api/health"                                              # public route
```

scope 檢查：把上面拿 token 的流程重做一次，`SCOPE="openid api/read"`，再跑：

```bash
hc -H "Authorization: Bearer $AT" "https://$APP/api/items"                # 有 api/read
hc -X POST -H "Authorization: Bearer $AT" -H 'Content-Type: application/json' -d '{}' "https://$APP/api/items"   # 沒有 api/write
```

名稱怎麼來的：client 名稱 `spa`、callback `https://app.<zone>/callback` 加 `local_dev_origins`、logout `https://app.<zone>/`、scope（`auth/user-pool.tf:4`、`:10-12`、`:27`）；client 固定 `generate_secret = false`、`code` flow、SRP 加 refresh（`modules/cognito-user-pool/main.tf:79-90`）；resource server identifier `api`（`auth/user-pool.tf:7`）。

**預期結果**

- client：`secret` 是 `null`；`flows` 是 `["code"]`；scopes 是 `openid`、`email`、`api/read`、`api/write`；dev 的 callback 有 `https://app.<zone>/callback` 與 `http://localhost:5173/callback`，sit 只有前者；`authFlows` 是 `ALLOW_USER_SRP_AUTH`、`ALLOW_REFRESH_TOKEN_AUTH`；`revocation` 是 `true`。
- authorizer：一個 `cognito`，`JWT`，`$request.header.Authorization`，issuer 等於 `$ISSUER`，audience 是 `[$CLIENT_ID]`。
- route：`GET /api/health` 是 `NONE`；`GET /api/items` 是 `JWT` 加 `api/read`；`POST /api/items` 是 `JWT` 加 `api/write`。
- access token 的 claim：`iss` 等於 `$ISSUER`、`client_id` 等於 `$CLIENT_ID`、沒有 `aud`、`token_use` 是 `access`、`scope` 含 `api/read api/write`。
- 沒有 token：`401`。有 token 經 CloudFront：`200`。直接打 execute-api：`200`。
- **經 CloudFront `401`、直接打 `200`**：`Authorization` header 沒有經 CloudFront 轉送（〈結論〉第 2 點成立）。記在備註、開 issue，第 3 項同時記為不通過。
- POST：`200` 或 `201`（看應用程式）。
- id token：`403`（推測：有 `aud` 能過 audience 檢查，但沒有 `scope` claim）。改壞簽章：`401`。`/api/health`：`200`。
- 只有 `api/read` 的 token：GET `200`、POST `403`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／經 CloudFront 與直接打的 GET 狀態碼 ______

## 6. origin verify 換值

**前提**

- 第 3、4 項通過。
- 應用程式同時接受 secret 的 `AWSCURRENT` 與 `AWSPREVIOUS`，快取最多 5 分鐘（REFERENCE〈應用程式合約〉第二列）。沒做雙值比對時，這一項一定會看到 `403`（`REFERENCE.md:178`）。
- 換值步驟照 REFERENCE〈runbook：換 origin verify 的值〉（`REFERENCE.md:150-178`），本文只加觀測。

**指令**

開始前，另開一個 shell 持續打 API（唯讀），整個換值過程都開著：

```bash
LOG=$(mktemp)
while :; do printf '%s %s\n' "$(date +%T)" "$(curl -s -o /dev/null -w '%{http_code}' "https://$APP/api/health")"; sleep 2; done > "$LOG" &
PROBE=$!
echo "$LOG"
```

照 REFERENCE 的 4 步做，每一步之後跑對應的檢查：

1. 【寫入】寫入新值（`REFERENCE.md:154-159`）。然後：

   ```bash
   aws secretsmanager list-secret-version-ids --secret-id "$OV_SECRET" \
     --query 'Versions[].[VersionId,join(`,`,VersionStages),CreatedDate]' --output table
   ```

2. 等 5 分鐘。然後確認新舊值直接打都會過：

   ```bash
   ov_header AWSCURRENT  | hc -H @- "https://$API_HOST/api/health"
   ov_header AWSPREVIOUS | hc -H @- "https://$API_HOST/api/health"
   ```

3. 【寫入】用新值 apply `web` 並等部署完成（`REFERENCE.md:163-168`）。然後：

   ```bash
   aws cloudfront get-distribution --id "$DIST" --query 'Distribution.Status' --output text
   ```

4. 【寫入】拿掉 `AWSPREVIOUS`（`REFERENCE.md:170-176`），記下舊版本的 `VersionId`。再等 5 分鐘：

   ```bash
   OLD=<舊版本的 VersionId>
   aws secretsmanager get-secret-value --secret-id "$OV_SECRET" --version-id "$OLD" --query SecretString --output text \
     | sed "s/^/$HDR: /" | hc -H @- "https://$API_HOST/api/health"
   ov_header AWSCURRENT | hc -H @- "https://$API_HOST/api/health"
   ```

結束後：

```bash
kill "$PROBE"
wc -l < "$LOG"
grep -v ' 200$' "$LOG" || echo "全程都是 200"
```

名稱怎麼來的：secret `<project>-<env>/origin-verify`（`foundation/secrets.tf:15`），值在 Terraform 外寫（`foundation/secrets.tf:1-2`）；CloudFront 端的值是 `web` 的 sensitive 變數（`web/variables.tf:11-20`）。

**預期結果**

- 第 1 步之後：新版本有 `AWSCURRENT`，舊版本有 `AWSPREVIOUS`。
- 第 2 步：兩個都是 `200`。
- 第 3 步：`Deployed`。
- 第 4 步：舊值 `403`、新值 `200`。舊版本拿掉標籤後還能不能用 `--version-id` 讀（推測：可以，直到 Secrets Manager 清掉沒有標籤的版本），讀不到就記在備註，這一步改成只確認新值 `200`。
- probe 全程都是 `200`。有 `403` 時記下時間點對應第幾步。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／probe 的非 200 筆數 ______

## 7. Lambda

**前提**

- 階段 D 完成；階段 F 已經用 `POST /api/items` 寫過一筆（第 5 項）。
- execution role 只有這張 table 與 index 的讀寫、兩個 secret 的 `GetSecretValue`、CMK 的 `Decrypt`、自己 log group 的寫入（`iam/policies.tf:8-39`），沒有 ECR 權限。Lambda 建立時用 apply 身分拉映像（`api/function.tf:1-2`）。
- table、兩個 secret、Lambda 的 log group 都用共用 CMK（`data/table.tf:6`、`foundation/secrets.tf:20`、`api/function.tf:45`）。

**指令**

```bash
aws lambda get-function --function-name "$PREFIX-api" --query 'Configuration.{state: State, update: LastUpdateStatus,
  reason: StateReason, pkg: PackageType, arch: Architectures, mem: MemorySize, timeout: Timeout, role: Role,
  log: LoggingConfig.LogGroup, envKms: KMSKeyArn, env: keys(Environment.Variables)}'
aws lambda get-function --function-name "$PREFIX-api" --query 'Code.{image: ImageUri, resolved: ResolvedImageUri}'
aws lambda get-function-concurrency --function-name "$PREFIX-api"
aws lambda get-account-settings --query 'AccountLimit.{total: ConcurrentExecutions, unreserved: UnreservedConcurrentExecutions}'
aws lambda get-policy --function-name "$PREFIX-api" --query Policy --output text | jq '.Statement[] | {Sid, Principal, Action, Condition}'

# 映像與 repository policy（Lambda 會不會自己加 statement）
aws ecr describe-images --repository-name "$PREFIX-api" --query 'imageDetails[].[imageTags[0],imagePushedAt]' --output text
aws ecr get-repository-policy --repository-name "$PREFIX-api" --query policyText --output text 2>&1 | head -40

# execution role
aws iam get-role --role-name "$PREFIX-api-lambda" --query 'Role.AssumeRolePolicyDocument' --output json
aws iam list-role-policies --role-name "$PREFIX-api-lambda"
aws iam list-attached-role-policies --role-name "$PREFIX-api-lambda"

# log group 的 CMK 與保留天數；log 裡沒有權限錯誤
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/$PREFIX-api" \
  --query 'logGroups[].[logGroupName,kmsKeyId,retentionInDays]' --output text
aws logs filter-log-events --log-group-name "/aws/lambda/$PREFIX-api" --start-time "$(since 3600)" \
  --filter-pattern '?AccessDenied ?AccessDeniedException ?KMS ?"not authorized"' --output json | jq -r '.events[].message' | head -20

# role 讀 secret 與解密都成功（CloudTrail 管理事件）
for ev in GetSecretValue Decrypt; do
  aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=$ev --max-results 50 --output json \
    | jq -r --arg r "$PREFIX-api-lambda" '.Events[].CloudTrailEvent | fromjson
      | select((.userIdentity.arn // "") | contains($r))
      | "\(.eventTime) \(.eventName) \(.requestParameters.secretId // .requestParameters.encryptionContext // "-" | tostring) \(.errorCode // "OK")"'
done

# table
aws dynamodb describe-table --table-name "$TABLE" --query 'Table.{status: TableStatus, keys: KeySchema, sse: SSEDescription,
  billing: BillingModeSummary.BillingMode, deletionProtection: DeletionProtectionEnabled}'
aws dynamodb describe-continuous-backups --table-name "$TABLE" --query 'ContinuousBackupsDescription.PointInTimeRecoveryDescription'
aws dynamodb scan --table-name "$TABLE" --select COUNT --query Count
```

【寫入】（選做，只在 dev）換版也要拉得到映像：照 REFERENCE〈runbook：發布 SPA 與 API 新版本〉推一個新 tag、改 `api_image_tag`、apply `api`，再跑上面前兩個指令。

名稱怎麼來的：function 名稱（`api/function.tf:6`，跟 `iam/naming.tf:5` 同一規則）；映像 `<repository>:<api_image_tag>`（`api/function.tf:7`），repository `<project>-<env>-api`（`containerimage/repositories.tf:4`），tag 不可變（`modules/ecr-repository/main.tf:3`）；arm64、512、10（`api/function.tf:9-11`）；環境變數 4 個（`api/function.tf:15-20`）；Lambda permission 的 `Sid` 是 `permissions` 的 key `apigateway`（`api/function.tf:22`、`modules/lambda-function/main.tf:124`），`source_arn` 是 `<execution_arn>/*/*`（`api/function.tf:24`）；role `<project>-<env>-api-lambda`，信任 `lambda.amazonaws.com` 加 `aws:SourceAccount`（`iam/roles.tf:4-5`）；log group `/aws/lambda/<name>`（`modules/lambda-function/main.tf:7`）；table `<project>-<env>-app`（`data/table.tf:5`）。`iam-role-policy` 掛的是 inline 還是 managed policy 沒有在本文確認，所以兩種都列。

**預期結果**

- `state` 是 `Active`、`update` 是 `Successful`、`Image`、`["arm64"]`、512、10；`role` 是 `<project>-<env>-api-lambda`；`log` 是 `/aws/lambda/<project>-<env>-api`；`env` 是 `API_SECRET_ARN`、`ORIGIN_VERIFY_HEADER_NAME`、`ORIGIN_VERIFY_SECRET_ARN`、`TABLE_NAME`。
- `envKms` 是 `null`：環境變數用 AWS managed key。REFERENCE `:203` 寫 Lambda 的環境變數用共用 CMK，跟程式碼不一致（見文末〈發現〉）。
- `resolved` 是 `@sha256:` 結尾，tag 等於 tfvars 的 `api_image_tag`。
- reserved concurrency 等於 tfvars；記下帳號的 `total` 與 `unreserved`。
- Lambda policy 一條：`Sid` `apigateway`，principal `apigateway.amazonaws.com`，`AWS:SourceArn` 是 `arn:aws:execute-api:<region>:<account>:<api id>/*/*`。
- repository policy：記下是「不存在」還是 Lambda 自己加了一條（推測：同帳號時 Lambda 可能在建立 function 時加）。`containerimage` 不管 repository policy，所以兩種都不會造成 drift；但如果有，下次 `containerimage` 的 plan 也要是「No changes」。
- trust policy 只有 `lambda.amazonaws.com`，條件 `aws:SourceAccount` 等於帳號。
- log group 的 `kmsKeyId` 等於 `$KMS_ARN`，保留天數 dev 30、sit 90。log 沒有權限錯誤。
- CloudTrail：`GetSecretValue` 有 `<project>-<env>/api-key` 或 `origin-verify`（看應用程式讀了哪些），都是 `OK`；`Decrypt` 都是 `OK`。
- table：`ACTIVE`、`PK`（HASH）與 `SK`（RANGE）、SSE `KMS` 且 key 是 `$KMS_ARN`、`PAY_PER_REQUEST`、刪除保護 dev 關 sit 開；PITR `ENABLED`，天數 dev 7、sit 35；`Count` 大於 0。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／repository policy 的狀態 ______

## 8. HTTP API access log

**前提**

- 階段 D 完成，第 3–5 項打過 API。
- access log group 用共用 CMK（`api/api.tf:27-31`），key policy 放行 `logs.<region>.amazonaws.com`，條件是 `kms:EncryptionContext:aws:logs:arn` 符合本帳號的 log group（`foundation/kms.tf:7-13`）。
- 範本沒有設定帳號層的 API Gateway CloudWatch role（那是 REST API 的設定）。`apigateway-http` 的 README 說 API Gateway 會用 CloudWatch Logs 的 resource policy 寫入，apply 身分要有 `logs:CreateLogDelivery`、`logs:PutResourcePolicy`（`modules/apigateway-http/README.md:56`）。

**指令**

```bash
aws logs describe-log-groups --log-group-name-prefix "/aws/apigateway/$PREFIX-api-access" \
  --query 'logGroups[].[logGroupName,kmsKeyId,retentionInDays,storedBytes]' --output text
aws apigatewayv2 get-stage --api-id "$API_ID" --stage-name '$default' --query 'AccessLogSettings'
aws logs filter-log-events --log-group-name "/aws/apigateway/$PREFIX-api-access" --start-time "$(since 3600)" --limit 5 \
  --output json | jq '.events[].message | fromjson'

# 帳號層的設定：REST API 的 CloudWatch role 預期沒有也能寫
aws apigateway get-account --query cloudwatchRoleArn --output text
aws logs describe-resource-policies --query 'resourcePolicies[].[policyName,lastUpdatedTime]' --output text
aws iam get-role --role-name AWSServiceRoleForAPIGateway --query Role.Arn --output text 2>&1
```

名稱怎麼來的：log group 名稱（`api/api.tf:28`），保留天數 `log_retention_days`（`api/envs/<env>.tfvars:14`）；log 格式固定 16 個欄位（`modules/apigateway-http/main.tf:5-22`）；stage 的 access log 設定（`modules/apigateway-http/main.tf:92-95`）。`AWSServiceRoleForAPIGateway` 是 AWS 的 service-linked role 名稱，推測。

**預期結果**

- log group 的 `kmsKeyId` 是 `$KMS_ARN`，保留天數 dev 30、sit 90，`storedBytes` 大於 0（剛寫入時可能還是 0，隔幾分鐘再看）。
- stage 的 `DestinationArn` 是這個 log group，`Format` 是 JSON。
- log 是 JSON，有 `requestId`、`routeKey`、`status`、`domainName`、`authorizerError` 等欄位，沒有 JWT claim 與 header；`401` 的請求 `authorizerError` 有值。
- `cloudwatchRoleArn` 是空的（`None`）而 log 照樣寫得進去：§5.6、§14「不需要帳號層的 role」成立。
- 記在備註：`describe-resource-policies` 有沒有跟 API Gateway 有關的 policy（看名稱與建立時間是否跟 `api` 的 apply 同時）、service-linked role 存不存在。這兩個是 REFERENCE〈執行 apply 的身分要有的權限〉要不要補 `logs:PutResourcePolicy` 的依據。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／resource policy 與 SLR 的狀態 ______

## 9. CloudFront log

**前提**

- 階段 D 完成，第 2–5 項產生過流量。
- delivery source、destination、delivery 都建在 us-east-1，destination 是 ap-northeast-1 的 log bucket（`web/logs.tf:5-8`）。`log-delivery` 的 README 寫明這個組合沒有實測（`modules/log-delivery/README.md:79`）。
- log bucket 用 SSE-S3，policy 放行 `delivery.logs.amazonaws.com` 寫 `AWSLogs/<account>/*`，`aws:SourceArn` 是本帳號任何 region 的 delivery source（`modules/s3-bucket/main.tf:32-56`）。

**指令**

```bash
aws logs describe-delivery-sources --region us-east-1 \
  --query "deliverySources[?name=='$PREFIX-web-access'].{name: name, type: logType, service: service, arns: resourceArns}"
aws logs describe-delivery-destinations --region us-east-1 \
  --query "deliveryDestinations[?name=='$PREFIX-web-bucket'].{name: name, type: deliveryDestinationType, dest: deliveryDestinationConfiguration.destinationResourceArn}"
aws logs describe-deliveries --region us-east-1 --query "deliveries[?deliverySourceName=='$PREFIX-web-access']"

aws s3api get-bucket-location --bucket "$LOG_BUCKET" --output text
aws s3api get-bucket-encryption --bucket "$LOG_BUCKET" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault'
aws s3api get-bucket-policy --bucket "$LOG_BUCKET" --query Policy --output text | jq '.Statement[] | {Sid, Action, Resource, Condition}'

# 流量後約 10 分鐘
aws s3 ls "s3://$LOG_BUCKET/" --recursive | tail -5
```

最後確認 bucket policy 沒有 drift（CloudWatch Logs 建 delivery 時可能自己改 policy，`modules/s3-bucket/main.tf:29-31`）：

```bash
./stacks.sh "$E" web plan       # 需要 TF_VAR_origin_verify_header_value
```

名稱怎麼來的：source 名稱 `"${var.name_prefix}-${each.key}"`（`modules/log-delivery/main.tf:18`），`name_prefix` 是 `<project>-<env>-web`、key `access`（`web/logs.tf:6`、`:17`）；destination 同規則，key `bucket`（`modules/log-delivery/main.tf:38`、`web/logs.tf:7`）；bucket 的 `vended_logs` 與保留天數（`web/buckets.tf:13-17`）。S3 上的實際路徑（例如 `AWSLogs/<account>/CloudFront/...`）是 CloudFront 的預設，推測。

**預期結果**

- source `<project>-<env>-web-access`，`ACCESS_LOGS`，`resourceArns` 是 distribution ARN。
- destination `<project>-<env>-web-bucket`，type `S3`，目標是 log bucket 的 ARN。
- delivery 一個，連接這兩者。
- bucket 在 `ap-northeast-1`，`AES256`；policy 有 `AllowVendedLogsWrite`、`AllowVendedLogsAclCheck`。
- 流量後 bucket 有新物件，路徑在 `AWSLogs/<account>/` 底下。
- `web plan` 是「No changes」。
- 不通過時記下是哪一種：`web` apply 在建 delivery 時就失敗（記錯誤訊息，表示跨 region 不支援，§11 第 10 點不成立，要改成 us-east-1 的 bucket）；delivery 建得起來但沒有物件（看 bucket policy 的 `Resource` 前綴跟實際寫入路徑對不對得上）；或 plan 有 drift。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／物件路徑 ______

## 10. WAF

**前提**

- 階段 D、E 完成。CloudFront WAF 一律開（`web/waf.tf:1-2`）：兩個 managed rule group、每個 IP 每 5 分鐘 2000 次（`web/waf.tf:7-11`、`web/envs/<env>.tfvars:9`）。
- log 進 us-east-1 的 `aws-waf-logs-<project>-<env>-web`，沒有 CMK，遮蔽 `authorization`、`cookie` 與 origin verify header（`web/waf.tf:13-16`、`modules/waf-web-acl/main.tf:18`）。origin verify header 是 CloudFront 回源時才加的，WAF 看的是 viewer 的請求，正常情況 log 裡不會有它；遮蔽是防 client 自己送。

**指令**

```bash
WAF_ARN=$(aws cloudfront get-distribution --id "$DIST" --query Distribution.DistributionConfig.WebACLId --output text)
echo "$WAF_ARN"
aws wafv2 get-web-acl --scope CLOUDFRONT --region us-east-1 --name "$PREFIX-web" --id "${WAF_ARN##*/}" \
  --query 'WebACL.{default: DefaultAction, rules: Rules[].{name: Name, priority: Priority,
           limit: Statement.RateBasedStatement.Limit, key: Statement.RateBasedStatement.AggregateKeyType,
           group: Statement.ManagedRuleGroupStatement.Name}}'
aws wafv2 get-logging-configuration --region us-east-1 --resource-arn "$WAF_ARN" \
  --query 'LoggingConfiguration.{dest: LogDestinationConfigs, redacted: RedactedFields[].SingleHeader.Name}'
aws logs describe-log-groups --region us-east-1 --log-group-name-prefix "aws-waf-logs-$PREFIX-web" \
  --query 'logGroups[].[logGroupName,retentionInDays,kmsKeyId]' --output text
```

觸發 managed rules（這些請求只會被擋，不改任何狀態）：

```bash
hc -G --data-urlencode 'q=<script>alert(1)</script>' "https://$APP/"          # CommonRuleSet 的 XSS
hc -H 'X-Api-Version: ${jndi:ldap://example.invalid/a}' "https://$APP/"        # KnownBadInputs 的 Log4j
hc -H "$HDR: runbook-redaction-check" "https://$APP/"                         # 遮蔽測試，應該是 200
```

約 5 分鐘後看 log：

```bash
aws logs filter-log-events --region us-east-1 --log-group-name "aws-waf-logs-$PREFIX-web" --start-time "$(since 900)" \
  --filter-pattern '{ $.action = "BLOCK" }' --output json \
  | jq -r '.events[].message | fromjson | [.terminatingRuleId, .httpRequest.uri, .httpRequest.args] | @tsv'
aws logs filter-log-events --region us-east-1 --log-group-name "aws-waf-logs-$PREFIX-web" --start-time "$(since 900)" \
  --filter-pattern '"runbook-redaction-check"' --query 'length(events)'
aws logs filter-log-events --region us-east-1 --log-group-name "aws-waf-logs-$PREFIX-web" --start-time "$(since 900)" \
  --output json | jq -c '.events[].message | fromjson | .httpRequest.headers[] | select(.name | ascii_downcase | IN("x-origin-verify","authorization","cookie"))' | sort -u
```

【寫入】rate limit（會擋掉你的 IP 幾分鐘，放在最後做）。打 S3 的靜態檔，不打 API，避免消耗 Lambda：

```bash
for round in 1 2 3 4 5 6; do
  echo "== round $round"
  seq 1 500 | xargs -P 20 -I{} curl -s -o /dev/null -w '%{http_code}\n' "https://$APP/index.html" | sort | uniq -c
done
```

再看 log 的 `terminatingRuleId` 有沒有 `rate-limit`（同上面第一個 log 指令）。

名稱怎麼來的：web ACL 名稱 `<project>-<env>-web`（`web/waf.tf:5`），`CLOUDFRONT` 時建在 us-east-1（`modules/waf-web-acl/main.tf:23`）；rate limit 規則名稱 `rate-limit`、priority 30（`modules/waf-web-acl/main.tf:5`、`:112`）；managed rule 的名稱是 `"${vendor}-${name}"`、priority 從 100 起（`modules/waf-web-acl/main.tf:6`、`:12`），vendor 預設 `AWS`（`modules/waf-web-acl/variables.tf:62`）；log group `aws-waf-logs-<name>`（`modules/waf-web-acl/main.tf:20`）。WAF log 裡被遮蔽的 header 值長什麼樣子（例如 `REDACTED`）是 WAF 的格式，推測。

**預期結果**

- `WAF_ARN` 是 `arn:aws:wafv2:us-east-1:<account>:global/webacl/<project>-<env>-web/<id>`。
- 預設動作 `Allow`；規則三條：`rate-limit`（30，2000，`IP`）、`AWS-AWSManagedRulesCommonRuleSet`（100）、`AWS-AWSManagedRulesKnownBadInputsRuleSet`（101）。
- logging 指到 us-east-1 的 log group，遮蔽 `authorization`、`cookie`、`x-origin-verify`；log group 的保留天數 dev 30、sit 90，沒有 `kmsKeyId`。
- XSS 與 Log4j 兩個請求都是 `403`，log 的 `terminatingRuleId` 分別是 CommonRuleSet 與 KnownBadInputs；遮蔽測試是 `200`。
- `runbook-redaction-check` 在 log 裡找不到（`0`）；最後一個指令列出的 header 值都不是原文。
- rate limit：累計超過約 2000 次之後開始出現 `403`（WAF 有延遲，記下大約第幾輪），log 有 `rate-limit` 的 `BLOCK`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／rate limit 從第幾輪開始擋 ______

## 11. Cognito

**前提**

- 階段 D 完成。user pool `ESSENTIALS`、MFA `OPTIONAL`、寄信用 `COGNITO_DEFAULT`（`auth/user-pool.tf:16-18`、`modules/cognito-user-pool/main.tf:40-42`）。
- 只有管理者能建使用者（module 預設，`modules/cognito-user-pool/variables.tf:37`；`auth` 沒有覆寫），Cognito 會寄含臨時密碼的邀請信。
- `COGNITO_DEFAULT` 每個帳號每天 50 封，邀請、驗證碼、忘記密碼都算（`modules/cognito-user-pool/README.md:50`）。這一項只寄 1 封；sit 要做大量測試前先算額度。

**指令**

```bash
aws cognito-idp describe-user-pool --user-pool-id "$POOL_ID" --query 'UserPool.{name: Name, tier: UserPoolTier, mfa: MfaConfiguration,
  email: EmailConfiguration, adminOnly: AdminCreateUserConfig.AllowAdminCreateUserOnly, deletion: DeletionProtection,
  domain: Domain, usernameAttrs: UsernameAttributes, autoVerified: AutoVerifiedAttributes}'
aws cognito-idp describe-user-pool-domain --domain "${COGNITO_DOMAIN%%.*}" --query 'DomainDescription.{status: Status, pool: UserPoolId}'
aws cognito-idp describe-resource-server --user-pool-id "$POOL_ID" --identifier api --query 'ResourceServer.{name: Name, scopes: Scopes[].ScopeName}'
```

【寫入】建測試使用者，會寄一封邀請信：

```bash
aws cognito-idp admin-create-user --user-pool-id "$POOL_ID" --username <test-email> \
  --user-attributes Name=email,Value=<test-email> Name=email_verified,Value=true --desired-delivery-mediums EMAIL \
  --query 'User.{status: UserStatus, created: UserCreateDate}'
```

收到信後，照第 5 項的網址用瀏覽器登入：輸入臨時密碼、設定新密碼（至少 12 字元，含大小寫與數字），MFA 是選用，可以跳過。

hosted UI 的導向檢查（`/logout`、`/oauth2/authorize` 與錯誤頁的行為是 Cognito 的慣例，推測）：

```bash
hc "https://$COGNITO_DOMAIN/logout?client_id=$CLIENT_ID&logout_uri=$(jq -rn --arg u "https://$APP/" '$u|@uri')"
hc "https://$COGNITO_DOMAIN/logout?client_id=$CLIENT_ID&logout_uri=$(jq -rn --arg u "https://evil.example/" '$u|@uri')"
hc "https://$COGNITO_DOMAIN/oauth2/authorize?response_type=code&client_id=$CLIENT_ID&redirect_uri=$(jq -rn --arg u "https://evil.example/callback" '$u|@uri')&scope=openid"
# dev 才有：本機開發的 callback 能用
hc "https://$COGNITO_DOMAIN/oauth2/authorize?response_type=code&client_id=$CLIENT_ID&redirect_uri=$(jq -rn --arg u "http://localhost:5173/callback" '$u|@uri')&scope=openid"
```

做完第 5、6 項之後，【寫入】刪掉測試使用者：

```bash
aws cognito-idp admin-delete-user --user-pool-id "$POOL_ID" --username <test-email>
```

名稱怎麼來的：user pool 名稱 `<project>-<env>-users`（`auth/user-pool.tf:16`）；`deletion_protection` 來自 `auth/envs/<env>.tfvars:9`（dev `false`、sit `true`），module 轉成 `ACTIVE`／`INACTIVE`（`modules/cognito-user-pool/main.tf:6`）；`domain_prefix` 來自 `auth/envs/<env>.tfvars:6`（`modules/cognito-user-pool/main.tf:51-54`）；resource server `api`，名稱 `<project>-<env>-api`，scope `read`、`write`（`auth/user-pool.tf:21-26`）；使用者名稱是 email、自動驗證 email（`modules/cognito-user-pool/main.tf:7-8`）。

**預期結果**

- user pool：`<project>-<env>-users`、`ESSENTIALS`、`OPTIONAL`、`EmailSendingAccount = COGNITO_DEFAULT`、`adminOnly = true`、deletion dev `INACTIVE` sit `ACTIVE`、`domain` 是 `domain_prefix`、`usernameAttrs` 是 `["email"]`、`autoVerified` 是 `["email"]`。
- domain `ACTIVE`。resource server 的 scope 是 `read`、`write`。
- `admin-create-user` 回 `FORCE_CHANGE_PASSWORD`，幾分鐘內收到邀請信（記下寄件地址與幾分鐘到）。
- 登入頁打得開，改密碼後導回 `https://app.<zone>/callback?code=...`。
- logout 到註冊過的網址：`302`，導向 `https://app.<zone>/`；到沒註冊的網址：不會導向 `evil.example`（記下實際狀態碼與導向）。
- authorize 帶沒註冊的 `redirect_uri`：不會導向 `evil.example`（推測：導到 Cognito 的錯誤頁，`redirect_mismatch`）。dev 的 localhost callback：`200` 或導向登入頁，不是錯誤頁。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／邀請信幾分鐘到 ______

## 12. 告警

**前提**

- 階段 D 完成，SNS 的 email 訂閱已確認。topic 用共用 CMK（`foundation/alarms.tf:5`），key policy 放行 `cloudwatch.amazonaws.com` 與 `sns.amazonaws.com`（`foundation/kms.tf:14-15`）。
- 兩條告警：Lambda `Errors` 與 HTTP API `5xx`，5 分鐘 `Sum` ≥ 1（`api/alarms.tf:4-25`），比較方式、評估期數、missing data 用 module 預設（`modules/metric-alarm/variables.tf:13`、`:15`、`:17`）。
- 告警的指標要有資料才查得到，先做完第 3–5 項。

**要確認的告警名稱**

| 告警 | 名稱 | 出處 |
|---|---|---|
| Lambda 錯誤 | `<project>-<env>-api-lambda-errors` | `modules/metric-alarm/main.tf:2` 是 `"${var.name_prefix}-${replace(k, "_", "-")}"`；`name_prefix = "${local.name_prefix}-api"`（`api/alarms.tf:34`）；key `lambda_errors`（`api/alarms.tf:4`） |
| API 5xx | `<project>-<env>-api-api-5xx` | 同上；key `api_5xx`（`api/alarms.tf:15`） |

**指令**

```bash
aws cloudwatch describe-alarms --alarm-names "$PREFIX-api-lambda-errors" "$PREFIX-api-api-5xx" \
  --query 'MetricAlarms[].{name: AlarmName, state: StateValue, ns: Namespace, metric: MetricName, dims: Dimensions,
           stat: Statistic, period: Period, threshold: Threshold, op: ComparisonOperator, periods: EvaluationPeriods,
           missing: TreatMissingData, alarm: AlarmActions, ok: OKActions}'

# 告警的維度跟實際指標一致
aws cloudwatch list-metrics --namespace AWS/Lambda --metric-name Errors \
  --dimensions Name=FunctionName,Value="$PREFIX-api" --query 'Metrics[].Dimensions'
aws cloudwatch list-metrics --namespace AWS/ApiGateway --metric-name 5xx \
  --dimensions Name=ApiId,Value="$API_ID" --query 'Metrics[].Dimensions'

aws sns get-topic-attributes --topic-arn "$TOPIC" --query 'Attributes.KmsMasterKeyId' --output text
aws sns list-subscriptions-by-topic --topic-arn "$TOPIC" --query 'Subscriptions[].[Protocol,Endpoint,SubscriptionArn]' --output table
```

【寫入】通知路徑，兩條各打一次：

```bash
for a in lambda-errors api-5xx; do
  aws cloudwatch set-alarm-state --alarm-name "$PREFIX-api-$a" --state-value ALARM --state-reason "runbook 通知測試"
done
```

狀態會在下一次評估時回到實際值，回到 `OK` 時也會收到信（`ok_actions`）。

【寫入】`api-5xx` 的真實觸發（只在 dev）：把 Lambda 的 reserved concurrency 暫時設成 0，API Gateway 呼叫不到 Lambda 會回 5xx（推測：HTTP API 回 `500` 或 `503`）。

```bash
aws lambda put-function-concurrency --function-name "$PREFIX-api" --reserved-concurrent-executions 0
for i in $(seq 1 5); do hc "https://$APP/api/health"; done
#   5–10 分鐘內 $PREFIX-api-api-5xx 應該 ALARM
# 復原：apply api，讓 reserved concurrency 回到 tfvars 的值
./stacks.sh "$E" api apply
aws lambda get-function-concurrency --function-name "$PREFIX-api"
```

`lambda-errors` 的真實觸發要讓應用程式丟出錯誤，範本沒有固定的做法。應用程式有會失敗的測試路徑就用它；沒有就只驗通知路徑，記在備註。

**預期結果**

- 兩條告警都在，平常是 `OK`；`AWS/Lambda` `Errors` 維度 `FunctionName`，`AWS/ApiGateway` `5xx` 維度 `ApiId`；`Sum`、300、1、`GreaterThanOrEqualToThreshold`、1 期、`notBreaching`；`alarm` 與 `ok` 都是 `$TOPIC`。
- `list-metrics`：Lambda 有一組剛好是 `FunctionName` 的維度；API Gateway 的結果裡要有一組**只有** `ApiId` 的維度（其他組可能多 `Stage`）。只有帶 `Stage` 的組合時，告警看的是不存在的指標，因為 `notBreaching` 會一直是 `OK`，記為不通過。
- topic 的 `KmsMasterKeyId` 是 `$KMS_ARN`；訂閱的 `SubscriptionArn` 是完整 ARN，不是 `PendingConfirmation`。
- 兩次 `set-alarm-state` 都收到 email（證明 CloudWatch 能用 CMK 發到加密的 topic）。
- 真實觸發：`api-5xx` 變 `ALARM` 並收到信；apply 之後 reserved concurrency 回到 tfvars 的值，告警回 `OK`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／只驗了通知路徑的告警 ______

## 13. destroy

**前提**

- 只在 dev 做。其他項目都做完、結果都記下來。
- 先把會用到的值存在 shell 變數裡（上面的共用變數），destroy 之後 SSM 就讀不到了。另外存一份：`KMS_KEY_ID=${KMS_ARN##*/}`。
- `web` 的 destroy 也要 `TF_VAR_origin_verify_header_value`（`web/variables.tf:11-20` 沒有預設值，至少 16 字元）。
- 會擋住 destroy 的資源見 REFERENCE〈destroy〉（`REFERENCE.md:208-224`）。dev 的 `data`、`auth` 刪除保護是關的；下面用 `-var` 暫時打開，驗證 sit 的流程。

**指令**

依 `ORDER` 反向，一個 stack 一個 stack 做，記下每一步的時間與錯誤訊息。

```bash
# 1. web：先清空兩個 bucket（force_destroy 是 false）
aws s3 rm "s3://$BUCKET" --recursive                               # 【寫入】
aws s3 rm "s3://$LOG_BUCKET" --recursive                           # 【寫入】
date; ./stacks.sh dev web destroy; date                            # 【寫入】
#   log bucket 在 destroy 期間又收到 log 而刪不掉時：再清一次、再跑一次

# 2. api、iam
./stacks.sh dev api destroy                                        # 【寫入】
./stacks.sh dev iam destroy                                        # 【寫入】

# 3. data：驗證刪除保護的流程
./stacks.sh dev data apply -- -var deletion_protection=true        # 【寫入】暫時打開
./stacks.sh dev data destroy                                       # 【寫入】預期失敗
./stacks.sh dev data apply                                         # 【寫入】回到 tfvars 的 false
./stacks.sh dev data destroy                                       # 【寫入】

# 4. auth：同上
./stacks.sh dev auth apply -- -var deletion_protection=true        # 【寫入】
./stacks.sh dev auth destroy                                       # 【寫入】預期失敗
./stacks.sh dev auth apply                                         # 【寫入】
./stacks.sh dev auth destroy                                       # 【寫入】

# 5. certificate：記下距離 web destroy 結束多久
date; ./stacks.sh dev certificate destroy; date                    # 【寫入】失敗就等幾分鐘再跑，記下等了多久

# 6. dns：先看 zone 裡還剩什麼
aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" --query 'ResourceRecordSets[].[Name,Type]' --output text
./stacks.sh dev dns destroy                                        # 【寫入】
#   然後到上層網域刪掉 NS 委派（人工）

# 7. foundation
./stacks.sh dev foundation destroy                                 # 【寫入】

# 8. containerimage：先刪映像（force_delete 是 false）
aws ecr batch-delete-image --repository-name "$PREFIX-api" \
  --image-ids "$(aws ecr list-images --repository-name "$PREFIX-api" --query imageIds --output json)"   # 【寫入】
./stacks.sh dev containerimage destroy                             # 【寫入】
```

destroy 之後確認：

```bash
aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='$PREFIX-web'].[Id,Status]" --output text
aws acm list-certificates --region us-east-1 --query "CertificateSummaryList[?DomainName=='$APP'].CertificateArn" --output text
aws route53 list-hosted-zones-by-name --dns-name "$ZONE" --max-items 1 --query 'HostedZones[].Name' --output text
aws secretsmanager describe-secret --secret-id "$PREFIX/origin-verify" --query DeletedDate --output text
aws secretsmanager describe-secret --secret-id "$PREFIX/api-key" --query DeletedDate --output text
aws kms describe-key --key-id "$KMS_KEY_ID" --query 'KeyMetadata.[KeyState,DeletionDate]' --output text
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/$PREFIX-api" --query 'logGroups[].logGroupName' --output text
aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 --query "WebACLs[?Name=='$PREFIX-web'].Name" --output text
aws logs describe-log-groups --region us-east-1 --log-group-name-prefix "aws-waf-logs-$PREFIX-web" --query 'logGroups[].logGroupName' --output text
```

名稱怎麼來的：兩個 bucket 的 `force_destroy` 用 module 預設 `false`（`modules/s3-bucket/variables.tf:171-173`）；zone 的 `force_destroy` 預設 `false`（`modules/route53-zone/variables.tf:34-36`）；ECR `force_delete = false`（`modules/ecr-repository/main.tf:4`）；secret 的保留 7 天（`foundation/secrets.tf:21`）；CMK 的刪除等待用 module 預設 30 天（`modules/kms-key/variables.tf:19`，`foundation/kms.tf:19-27` 沒有覆寫）；distribution 的 `comment` 預設是 `name`（`modules/cloudfront-distribution/main.tf:56`）；`stacks.sh` 把 `--` 之後的參數放在 `-var-file` 後面（`stacks.sh:125-126`），所以 `-var` 會蓋過 tfvars。

**預期結果**

- `web`：bucket 清空後 destroy 成功，花十幾分鐘（停用 distribution 要等部署）。記下 log bucket 有沒有在 destroy 期間又被寫入。
- `data`、`auth`：保護打開時 destroy 失敗，錯誤訊息看得出是刪除保護；`apply` 關掉之後 destroy 成功。
- `certificate`：記下 `web` 結束後多久才刪得掉。一次就成功、或第一次失敗（憑證還在使用中）等幾分鐘後成功，都算通過，但要把等待時間寫進 REFERENCE〈destroy〉。
- `dns`：destroy 前 zone 只剩 `NS` 與 `SOA`（`app` 的 alias 與驗證 record 已經隨 `web`、`certificate` 刪掉）；destroy 成功。
- `foundation`：成功；兩個 secret 有 `DeletedDate`；CMK 是 `PendingDeletion`，`DeletionDate` 約 30 天後。
- `containerimage`：映像刪掉後 destroy 成功。
- 確認指令：distribution、憑證、zone、web ACL、WAF log group 都查不到；Lambda 的 log group 查不到（如果還在，記下是不是 destroy 之後又被呼叫而重建）。
- 7 天內要在同一個 env 重新 apply 時，`foundation` 會因為 secret 名稱還在保留期而失敗（推測：Secrets Manager 不允許同名重建），要先 `restore-secret` 或等滿 7 天。記下實際錯誤訊息。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／憑證等了幾分鐘才刪得掉 ______

---

## 發現：文件與程式碼不一致

寫這份 runbook 時從程式碼找到的，都沒有修，交給負責範本的人決定：

1. `REFERENCE.md:203` 說 Lambda 的環境變數用共用 CMK。`api/function.tf:30-46` 沒有給環境變數的 KMS key，`lambda-function` 也只有 `log_kms_key_arn`（`modules/lambda-function/variables.tf:117`），所以環境變數用 AWS managed key。第 7 項的 `envKms` 會是 `null`。
2. README〈第一次 apply〉與 `REFERENCE.md:89-95` 的步驟直接 `apply`，沒有先 `./stacks.sh <env> <stack> init`。`stacks.sh` 的 `apply` 不會自動 init（`stacks.sh:119`、`:125`），全新的 checkout 照文件做會失敗。
3. `modules/apigateway-http/README.md:56` 說 apply 身分要有 `logs:CreateLogDelivery`、`logs:PutResourcePolicy`；REFERENCE〈執行 apply 的身分要有的權限〉（`REFERENCE.md:195-206`）的 `api` 列沒有這兩個。第 8 項的結果決定要不要補。

## 結果怎麼回寫

執行人是負責 apply 的專案 app team 成員；回寫分三處，都用 PR：

| 回寫到哪裡 | 誰改 | 怎麼改 | 誰審 |
|---|---|---|---|
| 本 runbook 的「結果紀錄」 | 執行人 | 每一項填完那一行；不通過的附 issue 連結 | 跟下一列同一個 PR |
| `templates/example6/infra/REFERENCE.md`〈雲端整合待驗證〉表（`:278-296`） | 執行人 | 表格加一欄「結果」，寫 `通過（YYYY-MM-DD，dev）` 或 `不通過：<一句話>（#issue）`。13 項都通過時，比照〈靜態驗證通過（2026-10-28）〉另開一節〈雲端驗證通過（日期）〉把表搬過去；〈已知限制的細節〉裡已經確認的條目改寫成確認後的事實；README 開頭的狀態句（`README.md:11`）與 REFERENCE 的狀態句（`REFERENCE.md:5`）改成實際狀態；第 13 項量到的憑證等待時間寫進〈destroy〉 | platform team ＋ 專案代表（`/templates/` 的 CODEOWNERS） |
| `docs/design/v9/design-docs.md` §11 | platform team | 每一點後面加 `→ 已確認（YYYY-MM-DD，runbook 第 <n> 項）`，或 `→ 不成立：<實際行為>，改法見 #issue`。不成立而要改設計的，在 §14 後面加一段記下決定 | platform team |
| module README 的「還沒在真實帳號 apply 過」或「未實測」 | platform team | 對應項目通過後改成實際驗證的日期與帳號類型：`acm-certificate`（第 1 項）、`route53-zone`、`route53-record`（第 1 項）、`cognito-user-pool`（第 5、11 項）、`apigateway-http`（第 3、4、8 項）、`secrets-manager-secret`（第 6、7 項）、`log-delivery` 的跨 region S3（第 9 項，`modules/log-delivery/README.md:79`） | platform team |

不通過的處理：

- 問題在 module（例如 `cloudfront-distribution`、`log-delivery`、`apigateway-http`）：照 `docs/guides/team-roles.md`〈交接點〉在本 repo 開 issue 給 platform team，附指令輸出。
- 問題在範本的 stack：開 issue 並標 `templates/example6`，修正走一般的範本改版 PR。
- 問題在應用程式（第 3–6 項的 origin verify、雙值比對）：開在專案自己的 repo；第 4 項不通過時，修好之前不要對外開放。
- 同一項修好後重跑，結果紀錄寫新的一行，舊的不刪。
