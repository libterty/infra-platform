# infra-platform v9 設計文件：邊緣層與 serverless module、example2 接 CDN、templates/example6

> 狀態：設計中，還沒實作。§3.1 的 D 是使用者拍板的決策；§3.2 的 K 是照慣例的判斷，審閱時可以推翻。標「審閱重點」的是需要特別看的取捨。
> 範圍：新增 7 個 module（Secrets Manager secret、ACM 憑證、Route 53 zone 與 record、CloudFront distribution、API Gateway HTTP API、Cognito user pool），3 個既有 module 升 minor（`waf-web-acl`、`s3-bucket`、`log-delivery`）。example2 加上 DNS、憑證與 CloudFront；新建 serverless 範本 `templates/example6`；範本裡 6 處自己宣告的 secret 改用新 module。帳號層的治理（CloudTrail、Config、GuardDuty、Security Hub、Backup、Budgets）不在這一版。
> 文中路徑除非特別註明，都是 repo 內相對路徑。provider schema 是 aws 6.70.0（`terraform providers schema -json`，2026-10-28）的結果。標「未確認」的要在實作或真實環境驗證。環境只有 `dev`、`sit`。

## 1. 結論

- **新 module 7 個**，每個發 0.1.0、在 HCP 登記。repo 的 module 從 73 個變成 80 個：`secrets-manager-secret`、`acm-certificate`、`route53-zone`、`route53-record`、`cloudfront-distribution`、`apigateway-http`、`cognito-user-pool`。全部用 aws provider，不用 awscc。
- **既有 module 升 minor 3 個**，只加輸入，預設值維持現在的行為：
  - `waf-web-acl` 0.2.0：加 `scope`，可以建 CloudFront 用的 web ACL。
  - `s3-bucket` 0.5.0：加 `cloudfront_distribution_arns`，讓 CloudFront 透過 OAC 讀 bucket。
  - `log-delivery` 0.2.0：加 `region`，CloudFront 的 log 來源必須建在 us-east-1。
- **us-east-1 的資源不用 provider alias**：aws 6.x 的 `aws_acm_certificate`、`aws_wafv2_*`、`aws_cloudwatch_log_group`、`aws_cloudwatch_log_delivery_*` 都有 resource 層級的 `region` 屬性（§2 第 1 點）。module 收 `region` 或 `scope`，stack 不用多宣告一個 provider。
- **secret 全部改用 module**：example2 到 example5 與 project-infra 的 `foundation/secrets.tf`，加上 project-infra 的 `agent/knowledge-bases.tf`，共 6 處。用 `moved` block 搬 address，不重建 secret。做完之後 `validate.sh` S8 的例外清單沒有任何 `resource`，範本 stack 全部只呼叫 module。
- **example2**：
  - 加兩個 stack：`dns`（每個環境一個子網域 zone）與 `certificate`（ALB 用的 regional 憑證、CloudFront 用的 us-east-1 憑證）。
  - 再加一個 `edge` stack：CloudFront distribution、CloudFront WAF、DNS record。
  - ALB 仍是 public，維持 origin verify header（D3），但改成 HTTPS listener。CloudFront 到 ALB 只走 HTTPS，header 不再明文經過網際網路（K7）。
- **example6**：serverless 範本。Cognito 登入、API Gateway HTTP API 加 JWT authorizer、Lambda（container image）、DynamoDB，前端是 S3 加 CloudFront 的 SPA。9 個 stack（§8）。
- **Phase**：I0–I10（§12）。module 先做（I1–I5），全部在 HCP 上之後才改範本（I6–I10）。

## 2. 查證發現

1. **aws 6.70.0 的 resource 層級 `region`**：`aws_acm_certificate`、`aws_wafv2_web_acl`、`aws_wafv2_ip_set`、`aws_wafv2_web_acl_logging_configuration`、`aws_cloudwatch_log_group`、`aws_cloudwatch_log_delivery_source` 都有 `region` 屬性。`aws_route53_record`、`aws_cloudfront_origin_access_control` 是全域服務，沒有這個屬性。所以 CloudFront 需要的 us-east-1 憑證與 WAF，可以由 module 用 `region = "us-east-1"` 建，不必在 stack 多宣告一個 provider alias。
2. **CloudFront 的 `custom_header.value` 不是 sensitive**：schema 沒有標 sensitive，所以 origin verify 的值會以明文出現在 plan 輸出與 state。module 要用獨立的 `sensitive = true` 變數收這個值（§5.5），plan 才會遮住它。state 仍然有明文。這跟 `alb` module 的 listener rule 已經把同一個值放進 `loadbalancer` 的 state 是同一級的暴露，不是新的風險類別（§4.1）。
3. **`aws_cloudfront_vpc_origin` 已存在**，CloudFront 可以直接連 internal ALB。使用者選擇維持 public ALB 加 origin verify header（D3），這個 resource 這一版不用。之後想把 ALB 收進私有網段時，再升 `cloudfront-distribution` 的 minor 版本，不影響這一版的設計。
4. **`aws_cognito_user_pool_client.client_secret` 是 sensitive 加 computed**：`generate_secret = true` 時，secret 會進 state。D5 決定只做 public client，module 固定 `generate_secret = false`。
5. **`aws_acm_certificate_validation`** 會等憑證簽發才結束。DNS 驗證要等上層網域的 NS 委派生效，委派還沒做時 apply 會一直等到 timeout。§7.2 的流程把委派排在 `dns` 和 `certificate` 兩個 stack 之間。
6. **API Gateway HTTP API 不能掛 WAF**：AWS WAF 能保護的是 REST API，不含 HTTP API（未確認，實作 I4 時查 AWS WAF 文件確認）。example6 的 API 改靠 throttling、JWT authorizer 與 Lambda 的 reserved concurrency 擋濫用（§4.3，審閱重點）。
7. **CloudFront 標準 log v2 走 vended log delivery**：delivery source 要建在 us-east-1。既有的 `log-delivery` module 沒有 `region` 輸入，要升 minor 版本。舊版的 `logging_config` 要求 bucket 開 ACL，跟 `s3-bucket` 強制 BucketOwnerEnforced 衝突，所以不用舊版。
8. **範本裡自己宣告 secret 的 6 處**：
   - example2、example3：`for_each` 兩個簽章 key，沒有指定 KMS，用 AWS managed key。
   - example4、example5：一個 OpenSearch master secret，用 foundation 的 CMK。
   - project-infra：`foundation` 的 `app`，加上 `agent` 每個 knowledge base 一個 `kb_db`。
   - v1 設計 §5.3 當初認為「只有一個 resource，包成 module 省不到東西」。現在要加 resource policy、rotation 與 validation，6 處的寫法也已經不一致，所以收進 module。

## 3. 決策

### 3.1 使用者拍板（2026-10-28）

| # | 決策 |
|---|---|
| D1 | 範圍：§1 的 7 個 module。帳號層治理另開一版 |
| D2 | example2 加 DNS、憑證、CloudFront、secret module；API Gateway 與 Cognito 放進新的 example6（serverless） |
| D3 | CloudFront 到 ALB 維持 public ALB 加 origin verify header，不用 VPC origin |
| D4 | 範本建每個環境的子網域 hosted zone（例如 `dev.example.com`），上層網域的 NS 委派由人手動做一次 |
| D5 | Cognito 只做 public client 加 PKCE，不產生 client secret |

### 3.2 照慣例的判斷（審閱時可以推翻）

| # | 判斷 | 理由 |
|---|---|---|
| K1 | 6 處 secret 全部改用 `secrets-manager-secret`，再把 S8 例外清單的兩條 secret 例外拿掉 | 範本 stack 全部只呼叫 module，例外清單只剩 `search-config` 的 ephemeral block |
| K2 | 搬遷用 `moved` block，KMS key 維持原狀：example2、example3 仍是 AWS managed key | 範本已經被複製出去的專案可能 apply 過；換 key 會改到既有 secret 的加密方式，不屬於這次重構 |
| K3 | secret module 永遠不建 `aws_secretsmanager_secret_version` | 沿用現有原則：值由人或輪替流程寫，不進 tfvars、SSM、state |
| K4 | us-east-1 的資源由 module 的 `region`／`scope` 輸入決定，stack 不宣告 provider alias | §2 第 1 點；stack 的 `providers.tf` 維持一個 provider，`expected_account_id` 等 guard 不用改 |
| K5 | `route53-record` 一次收一個 zone 的多筆 record（`records` map） | 跟 `iot-topic-rule` 的 `rules` 一樣；一筆一個 module 呼叫太囉唆 |
| K6 | `acm-certificate` 在 module 裡建 DNS 驗證 record 並等待簽發 | 憑證和驗證 record 永遠成對出現；拆開的話每個 stack 都要重寫同一段 `for_each` |
| K7 | CloudFront 到 ALB 只走 HTTPS（`https-only`），ALB 開 HTTPS listener | 現在的 ALB 只開 HTTP:80，CDN 送的 origin verify header 會明文經過網際網路 |
| K8 | CloudFront 轉送 viewer 的 Host header（managed policy `AllViewer`），ALB 憑證含 `api.<env>` 與 `origin-api.<env>` 兩個名稱 | 轉送 Host 時，CloudFront 用 Host 做 SNI 與憑證比對（未確認，I7 查 CloudFront 文件）；ALB listener rule 的 `host_headers` 不用改 |
| K9 | example2 的 ALB WAF 不動，`edge` 另外加一個 CloudFront WAF（managed rules 加 rate limit） | 只有 CloudFront 看得到 client 的真實 IP；ALB WAF 的 rate limit 在 CDN 後面會把整個 CloudFront edge 算成同一批 IP（§11） |
| K10 | Cognito 用 prefix domain（`<prefix>.auth.<region>.amazoncognito.com`），不做 custom domain | custom domain 要 us-east-1 憑證和 alias record，dev／sit 不需要 |
| K11 | Cognito 寄信用 `COGNITO_DEFAULT` | SES 不在這一版（D1）；`COGNITO_DEFAULT` 每天的寄信量有限（數字未確認），正式環境要換 SES |
| K12 | `apigateway-http` 的每條 route 都要明寫 authorizer 或 `public = true` | 沒寫就預設公開太危險，validation 擋掉 |
| K13 | example6 不做 VPC：Lambda 不進 VPC，DynamoDB 走公網 endpoint | DynamoDB 與 Secrets Manager 都不需要 VPC；省掉 NAT 的成本與 network stack |
| K14 | example6 的 CloudFront WAF 預設關（`web_waf_enabled = false`） | 前端是靜態檔，dev／sit 每個 web ACL 加規則每月約 10 美元以上（§10）；開關留給正式環境 |
| K15 | Phase 代號用 I，接在 v8 的 H 之後 | 慣例 |

## 4. trust boundary 與特權操作

| 邊界 | 誰跨過 | 控制 |
|---|---|---|
| 網際網路 → CloudFront | 所有使用者 | CloudFront WAF（managed rules、rate limit）、只接 HTTPS（`redirect-to-https`）、TLS 最低 `TLSv1.2_2021` |
| CloudFront → ALB（example2） | CloudFront edge | ALB SG 只開 CloudFront origin-facing prefix list 加 tfvars 的 CIDR、HTTPS、origin verify header 由 listener rule 檢查 |
| CloudFront → S3（example6） | CloudFront 服務 | OAC（SigV4），bucket policy 只允許 `cloudfront.amazonaws.com` 加 `AWS:SourceArn` 等於這個 distribution |
| 網際網路 → API Gateway（example6） | 已登入的使用者 | JWT authorizer 驗 Cognito issuer 與 audience、route 層級 scope、stage throttling |
| API Gateway → Lambda | API Gateway 服務 | `lambda-function` 的 `permissions`：`apigateway.amazonaws.com`，`source_arn` 限這個 API 的 execution ARN |
| Lambda → DynamoDB、Secrets Manager | Lambda execution role | `iam` stack 只給這張 table 與指定 secret 的 ARN |
| 人 → Secrets Manager | 維運人員 | 值不經 Terraform；resource policy 可以加 deny（§5.1） |

### 4.1 origin verify header 的值（審閱重點）

- 值仍然用 `TF_VAR_origin_verify_header_value` 給，不放 tfvars。v9 起 `loadbalancer` 和 `edge` 兩個 stack 都要這個值，兩邊必須一致。
- **plan 輸出**：module 的變數標 `sensitive`，plan 顯示 `(sensitive value)`。
- **state**：`edge` 的 state 有明文（§2 第 2 點）。state 只存在使用範本的專案自己的 S3 state bucket，`.gitignore` 擋 `*.tfstate`，不會進任何 repo；這個 repo 只做離線驗證，不產生 state。`loadbalancer` 的 state 原本就有明文，所以暴露面從一份 state 變成兩份，兩份都在同一個加密 state bucket，同一組權限控管。
- **傳輸**：K7 之後只在 TLS 裡傳。
- **換值**：先 apply `loadbalancer`，讓 listener rule 同時接受新舊兩個值；再 apply `edge`；最後拿掉舊值。實作時確認 `alb` module 的 `origin_verify_header_value` 能不能收兩個值；不能收的話，換值期間會中斷，要寫進 REFERENCE。

### 4.2 secret 的 resource policy

- module 收結構化的 statement，不收任意 JSON。
- validation 擋：`Principal` 是 `*` 又沒有 condition 的 `Allow`、`Action` 是 `secretsmanager:*` 的 `Allow`。
- 預設不建 policy，這時存取完全由 IAM 決定，跟現在一樣。

### 4.3 example6 的 API 沒有 WAF（審閱重點）

- HTTP API 掛不了 WAF（§2 第 6 點，未確認）。
- 補償控制：
  - JWT authorizer：除了 `public = true` 的 health check，其他 route 都要登入。
  - stage 預設 throttling：rate 與 burst，tfvars 可調。
  - Lambda 的 `reserved_concurrent_executions`：限制被打爆時的成本上限。
  - access log 進 CloudWatch Logs。
- 需要 WAF 時有兩條路：在 API 前面加一個 CloudFront 再掛 CloudFront WAF；或改用 REST API。兩條都不在這一版。

## 5. module 清單

| module | provider | resource | 用在 |
|---|---|---|---|
| `secrets-manager-secret` | aws | `aws_secretsmanager_secret`、`aws_secretsmanager_secret_policy`、`aws_secretsmanager_secret_rotation` | 所有範本的 `foundation`、project-infra `agent` |
| `route53-zone` | aws | `aws_route53_zone` | example2、example6 `dns` |
| `route53-record` | aws | `aws_route53_record` | example2 `edge`、example6 `api`、`web` |
| `acm-certificate` | aws | `aws_acm_certificate`、`aws_route53_record`（驗證用）、`aws_acm_certificate_validation` | example2、example6 `certificate` |
| `cloudfront-distribution` | aws | `aws_cloudfront_distribution`、`aws_cloudfront_origin_access_control`；data `aws_cloudfront_cache_policy` 等 managed policy | example2 `edge`、example6 `web` |
| `apigateway-http` | aws | `aws_apigatewayv2_api`、`_stage`、`_integration`、`_route`、`_authorizer`、`_domain_name`、`_api_mapping` | example6 `api` |
| `cognito-user-pool` | aws | `aws_cognito_user_pool`、`_user_pool_client`、`_user_pool_domain`、`_resource_server` | example6 `auth` |

共用的規則跟 v7、v8 一樣：

- 不建 IAM 與 security group（S4）、不用 `random_password`（S7）。
- `description` 用台灣繁體中文，註解與 `error_message` 用英文。
- README 表格由 terraform-docs 產生（S11），每個 module 有 `examples/basic` 與 `tests/`。

### 5.1 `secrets-manager-secret`

- 責任：一個 secret 的容器，加上選填的 resource policy 與輪替設定。不含值。
- 輸入：
  - `name`：1–512 字元，validation 擋結尾是 `-` 加 6 個字元。AWS 會在 ARN 加 6 字元的後綴，名稱自己長得像後綴會讓 ARN 比對出錯。
  - `description`。
  - `kms_key_arn`：`null` 時用 `aws/secretsmanager`。只收 key ARN，不收 alias。
  - `recovery_window_in_days`：7–30，預設 7；不收 0，避免刪了立刻消失。
  - `policy_statements`：list of `{ sid, effect, principals = { type, identifiers }, actions, conditions }`。
  - `rotation = { lambda_arn, automatically_after_days 或 schedule_expression, duration, rotate_immediately = false }`。
  - `tags`。
- validation：
  - `policy_statements` 擋 §4.2 的寬鬆 `Allow`。
  - `rotation` 的兩種排程擇一；`automatically_after_days` 1–1000。
  - Lambda ARN 格式。
- 輸出：`arn`、`name`、`id`。
- 刻意不做：
  - `aws_secretsmanager_secret_version`（K3）。
  - 跨 region replica。
  - managed external rotation（`external_secret_rotation_*`）。
  - 輪替 Lambda 本身：用 `lambda-function` 建，它的 `permissions` 給 `secretsmanager.amazonaws.com`。

### 5.2 `route53-zone`

- 責任：一個 hosted zone。
- 輸入：`name`、`comment`、`private_vpc_ids`（非空時建 private zone）、`force_destroy`（預設 `false`）、`tags`。
- validation：`name` 是合法的 DNS 名稱，結尾不帶 `.`；`private_vpc_ids` 是 `vpc-` 開頭。
- 輸出：`zone_id`、`name`、`name_servers`（private zone 時是空 list）、`arn`。
- 刻意不做：DNSSEC（`aws_route53_key_signing_key` 要 us-east-1 的 KMS key 與 key policy，另外處理）、query log、delegation set。

### 5.3 `route53-record`

- 責任：一個 zone 裡的多筆 record（K5）。
- 輸入：
  - `zone_id`。
  - `records`：key 是短名，值是 `{ name, type, ttl, values }` 或 `{ name, type, alias = { name, zone_id, evaluate_target_health } }`，兩種擇一。
- validation：
  - `type` 只能是 `A`、`AAAA`、`CNAME`、`TXT`、`MX`、`NS`、`CAA`、`SRV`。
  - alias 只能用在 `A`、`AAAA`；非 alias 時 `values` 非空、`ttl` 60–172800。
  - `CNAME` 只能有一個值。
- 固定：`allow_overwrite = false`。
- 輸出：`fqdns`（key → FQDN）。
- 刻意不做：routing policy（weighted、latency、failover）、health check。

### 5.4 `acm-certificate`

- 責任：一張 DNS 驗證的公開憑證，含驗證 record，並等待簽發（K6）。
- 輸入：
  - `domain_name`、`subject_alternative_names`。
  - `zone_id`：驗證 record 寫進這個 zone；憑證的所有名稱都要在這個 zone 底下。
  - `region`：`null` 用 provider 的 region；CloudFront 用時給 `"us-east-1"`。
  - `key_algorithm`：預設 `RSA_2048`，可選 `EC_prime256v1`、`EC_secp384r1`。
  - `validation_timeout`：預設 `"45m"`。
  - `tags`。
- validation：
  - 名稱合法；wildcard 只能在最左邊一層。
  - SAN 最多 9 個，加 `domain_name` 共 10 個，是 ACM 的預設上限。
  - `region` 是 AWS region 格式。
- 實作要點：
  - 驗證 record 用 `domain_validation_options` 做 `for_each`，key 是 `domain_name`。
  - apex 和 `*.apex` 會產生同一筆驗證 record，所以這筆 record 設 `allow_overwrite = true`。這是 module 內唯一的例外。
- 輸出：`certificate_arn`（取自 validation resource，所以等於「已簽發」）、`domain_name`。
- 刻意不做：email 驗證、匯入憑證、private CA 憑證（v8 有 `acm-pca`）、跨帳號的 zone。

### 5.5 `cloudfront-distribution`

- 責任：一個 distribution 和它需要的 OAC。
- 輸入：
  - `comment`、`aliases`、`certificate_arn`（validation：必須是 us-east-1 的 ACM ARN）。
  - `web_acl_arn`：`null` 或 global WAF ARN `arn:aws:wafv2:us-east-1:<帳號>:global/webacl/...`。
  - `price_class`：預設 `PriceClass_200`，含亞洲。
  - `origins`：key → `{ type = "s3" | "custom", domain_name, origin_path, custom = { https_port = 443, read_timeout = 30, keepalive_timeout = 5 } }`。
    - `s3` 時 module 建一個 OAC（`sigv4`、`always`）。
    - `custom` 時固定 `origin_protocol_policy = "https-only"`、`origin_ssl_protocols = ["TLSv1.2"]`。
  - `origin_verify = { origin, header_name }` 與 `origin_verify_header_value`（`sensitive`）：§2 第 2 點、§4.1。
  - `default_behavior` 與 `ordered_behaviors`：
    - 欄位：`origin`、`path_pattern`（只有 ordered 有）、`allowed_methods = "read" | "read_options" | "all"`。
    - `cache_policy`、`origin_request_policy`、`response_headers_policy` 收 managed policy 名稱，module 用 data source 查 ID。response headers 預設 `Managed-SecurityHeadersPolicy`。
  - `spa_fallback`（`bool`，預設 `false`）：`true` 時 403、404 回 `/index.html`，狀態碼 200。
  - `default_root_object`。
  - `geo_restriction = { type, locations }`。
  - `tags`。
- 固定：
  - `viewer_protocol_policy = "redirect-to-https"`、`minimum_protocol_version = "TLSv1.2_2021"`、`ssl_support_method = "sni-only"`。
  - `http_version = "http2and3"`、`is_ipv6_enabled = true`、`compress = true`。
- validation：
  - `aliases` 非空時必須給 `certificate_arn`。
  - behavior 指到的 origin 要存在。
  - `origin_verify.origin` 必須是 `custom` origin。
  - `ordered_behaviors` 的 `path_pattern` 不重複。
- 輸出：`distribution_id`、`arn`、`domain_name`、`hosted_zone_id`（alias record 用）、`oac_ids`。
- 刻意不做：
  - Lambda@Edge、CloudFront Functions、origin group（failover）。
  - signed URL（key group）、field-level encryption、continuous deployment、VPC origin（§2 第 3 點）。
  - logging：用 `log-delivery`，source 是 distribution ARN、`region = "us-east-1"`。

### 5.6 `apigateway-http`

- 責任：一個 HTTP API、`$default` stage、Lambda integration、JWT authorizer、route、選填的 custom domain。
- 輸入：
  - `name`、`description`。
  - `cors = { allow_origins, allow_methods, allow_headers, allow_credentials, max_age }`。
  - `jwt_authorizers`：key → `{ issuer, audience }`。
  - `integrations`：key → `{ lambda_arn, timeout_ms = 30000 }`，payload 固定 `2.0`。
  - `routes`：key 是 route key，例如 `"GET /items"`，值是 `{ integration, authorizer, scopes, public = false }`。
  - `throttling = { rate_limit, burst_limit }`：必填。
  - `access_log_group_arn`：必填，log format 固定一組 JSON 欄位。
  - `custom_domain = { domain_name, certificate_arn }`：regional 憑證。
  - `disable_execute_api_endpoint`：預設在有 `custom_domain` 時為 `true`。
  - `tags`。
- validation：
  - 每條 route 剛好二選一：有 `authorizer`，或 `public = true`（K12）。
  - authorizer 與 integration 的 key 要存在。
  - `issuer` 是 `https://`。
  - `allow_credentials = true` 時 `allow_origins` 不可有 `*`。
  - `timeout_ms` 50–30000。
  - throttling 是正數。
- 輸出：`api_id`、`api_endpoint`、`execution_arn`（給 `lambda-function` 的 `permissions`）、`stage_invoke_url`、`domain_target`（`{ name, zone_id }`，給 alias record）。
- 刻意不做：WebSocket API、VPC Link、Lambda authorizer、IAM authorizer、mTLS、多個 stage。HTTP API 的 access log 不需要 account 層的 CloudWatch role（未確認；REST API 才需要）。

### 5.7 `cognito-user-pool`

- 責任：一個 user pool、多個 public app client、prefix domain、選填的 resource server。
- 輸入：
  - `name`。
  - `user_pool_tier`：預設 `ESSENTIALS`。
  - `sign_in_attributes`：預設 `["email"]`。
  - `admin_create_user_only`：預設 `true`。
  - `mfa`：`OFF`、`OPTIONAL`、`ON`，預設 `OPTIONAL`，只用 TOTP。
  - `password_policy`：最短 12 字元，預設要求大小寫與數字。
  - `deletion_protection`：預設 `true`。
  - `domain_prefix`。
  - `resource_servers`：identifier → `{ name, scopes }`。
  - `clients`：key → `{ callback_urls, logout_urls, scopes, access_token_minutes = 60, id_token_minutes = 60, refresh_token_days = 30 }`。
  - `tags`。
- 固定（D5）：
  - `generate_secret = false`。
  - `allowed_oauth_flows = ["code"]`：不准 implicit。
  - `explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]`。
  - `prevent_user_existence_errors = "ENABLED"`、`enable_token_revocation = true`。
  - `account_recovery`：只用已驗證的 email。
- validation：
  - `callback_urls` 與 `logout_urls` 必須是 `https://`，只有 `http://localhost` 例外。
  - scope 是 `openid`、`email`、`profile` 或 `<resource server>/<scope>`，而且 resource server 存在。
  - `domain_prefix` 不含 `aws`、`amazon`、`cognito`（Cognito 保留字）。
  - token 有效期在 Cognito 允許範圍內。
- 輸出：`user_pool_id`、`user_pool_arn`、`issuer_url`（`https://cognito-idp.<region>.amazonaws.com/<pool id>`，給 JWT authorizer）、`client_ids`、`hosted_ui_url`。
- 刻意不做：
  - confidential client（D5）、identity pool、社群登入或 SAML／OIDC IdP。
  - Lambda trigger、custom domain（K10）、SES（K11）、managed login branding。

### 5.8 既有 module 的 minor 版

| module | 版本 | 新輸入 | 預設值 | 說明 |
|---|---|---|---|---|
| `waf-web-acl` | 0.1.1 → 0.2.0 | `scope = "REGIONAL" \| "CLOUDFRONT"` | `REGIONAL` | `CLOUDFRONT` 時 ip set、web ACL、log group、logging config 都設 `region = "us-east-1"`；README 的「給 ALB 用」改寫 |
| `s3-bucket` | 0.4.0 → 0.5.0 | `cloudfront_distribution_arns` | `[]` | 非空時 bucket policy 加一條 `s3:GetObject`，principal `cloudfront.amazonaws.com`，條件 `AWS:SourceArn` |
| `log-delivery` | 0.1.x → 0.2.0 | `region` | `null` | source、destination、delivery 都建在這個 region |

`s3-bucket` 用 SSE-KMS 時，CloudFront 要能 `kms:Decrypt`，由 `kms-key` 的 `service_principals` 給。example6 的前端 bucket 用 SSE-S3（`kms_key_arn = null`），避開這件事；內容本來就是公開的靜態檔。

## 6. secret 搬遷（I1）

| 範本 | stack | 現在 | 改成 | `moved` |
|---|---|---|---|---|
| example2、example3 | `foundation` | `aws_secretsmanager_secret.this["<key>"]`，沒有 KMS | `module.secrets["<key>"]` | 每個 key 一個 `moved`，`kms_key_arn = null`（K2） |
| example4、example5 | `foundation` | `aws_secretsmanager_secret.opensearch_master`，CMK | `module.opensearch_master_secret` | 一個 |
| project-infra | `foundation` | `aws_secretsmanager_secret.app`，CMK | `module.app_secret` | 一個 |
| project-infra | `agent` | `aws_secretsmanager_secret.kb_db["<kb>"]` | `module.kb_db_secret["<kb>"]` | `for_each` 的 key 是 tfvars 決定的，`moved` 要寫成 `module.kb_db_secret` 對 `aws_secretsmanager_secret.kb_db` 整組搬；Terraform 能不能整組搬 for_each 的 resource 進 module 要實測（未確認），不能時改在 REFERENCE 寫 `terraform state mv` 指令 |

- 同步改：
  - `validate.sh` 的 `s8_allowed` 拿掉 `foundation:aws_secretsmanager_secret` 與 `agent:aws_secretsmanager_secret`。
  - `docs/guides/project-infra-standard.md` 的〈例外清單〉。
  - 各範本 README 的「唯一自己宣告的 AWS resource」句子。
- 驗收：
  - 每個範本的 `foundation` 測試確認 secret 的名稱、KMS、recovery window 跟搬遷前一樣。
  - `terraform validate` 接受 `moved` block。
  - S8 用假 stack 確認 `aws_secretsmanager_secret` 現在會被擋。

## 7. example2 的變更

### 7.1 stack 與 ORDER

ORDER 從 11 個變成 14 個：

```
containerimage foundation dns certificate network database iam bridge loadbalancer edge agent application operation postdeploy
```

| stack | 狀態 | 建什麼 |
|---|---|---|
| `dns` | 新 | `route53-zone`：`<env>.example.com` |
| `certificate` | 新 | `acm-certificate` ×2：ALB 用的 regional 憑證（`api.<env>`、`origin-api.<env>`，K8）、CloudFront 用的 us-east-1 憑證（`api.<env>`） |
| `loadbalancer` | 改 | 從樹 B 讀 ALB 憑證 ARN，開 HTTPS listener；HTTP:80 只 redirect |
| `edge` | 新 | `cloudfront-distribution`（origin 是 `origin-api.<env>`，custom、HTTPS）、`waf-web-acl` 0.2.0（`scope = "CLOUDFRONT"`）、`route53-record`（`api` → CloudFront、`origin-api` → ALB）、`s3-bucket` 加 `log-delivery`（CloudFront log） |
| `network` | 改 tfvars | `alb_ingress` 範例改成 CloudFront origin-facing prefix list，加 dev 的辦公室 CIDR |
| `application` | 改 tfvars | `trusted_proxies` 改 `vpc_and_cdn` |
| `foundation` | 改 | secret 改用 module（§6） |

- `bridge` 多轉寫 4 個 key 到樹 B：`zone_id`、`zone_name`、`alb_certificate_arn`、`cloudfront_certificate_arn`。
- `edge` 讀樹 B 的 zone 與 CloudFront 憑證，再讀 `loadbalancer` 樹 A 的 ALB DNS 名稱與 zone ID。這符合「後段 stack 只讀樹 B 與其他後段 stack 的樹 A」的規則。
- `check-ssm-contract.sh` 會從 ORDER 檢查每個讀取都有寫入。

### 7.2 第一次 apply 的流程

這是複製範本的專案在自己帳號部署時的步驟，寫進範本的 README 與 REFERENCE。這個 repo 不 apply，實作時只需要把文件寫對，離線驗證不受影響。

1. `./stacks.sh dev dns apply`：輸出 4 個 NS。
2. 人在上層網域 `example.com` 加一筆 NS record，委派 `dev.example.com`。用 `dig NS dev.example.com +short` 確認委派生效。
3. `./stacks.sh dev all apply`：`certificate` 會等到憑證簽發。委派沒做的話，45 分鐘後 timeout 失敗（`validation_timeout`），錯誤訊息直接看得出原因。
4. 之後的 apply 不需要再等：憑證已簽發，到期前 ACM 自動續約。

README〈部署〉、REFERENCE〈第一次 apply〉要寫這段流程。`stacks.sh` 不改：沒有可靠的離線方式判斷委派完成。

### 7.3 SSM 合約（新增）

| key（樹 A，`/<project>/<env>/…`） | 寫的 stack | 讀的 stack |
|---|---|---|
| `dns/zone_id`、`dns/zone_name`、`dns/name_servers` | `dns` | `certificate`、`bridge` |
| `certificate/alb_certificate_arn`、`certificate/cloudfront_certificate_arn` | `certificate` | `bridge` |
| `edge/distribution_id`、`edge/domain_name` | `edge` | `postdeploy`（選用的 CloudFront 告警） |

key 的實際寫法照 example2 現有的命名，上表只表達誰寫誰讀。

## 8. templates/example6

### 8.1 stack 清單與 ORDER

```
containerimage foundation dns certificate auth data iam api web
```

| # | stack | 建什麼 | 主要 module |
|---|---|---|---|
| 1 | `containerimage` | API Lambda 的 ECR repository | `ecr-repository` |
| 2 | `foundation` | CMK、告警 SNS topic、第三方 API key 的 secret 容器 | `kms-key`、`sns-alarm-topic`、`secrets-manager-secret` |
| 3 | `dns` | `<env>.example.com` zone | `route53-zone` |
| 4 | `certificate` | API custom domain 的 regional 憑證（`api.<env>`）、前端的 us-east-1 憑證（`app.<env>`） | `acm-certificate` ×2 |
| 5 | `auth` | user pool、SPA client（callback 是 `https://app.<env>.example.com/callback`，dev 另加 `http://localhost:5173/callback`）、resource server `api`（scope `read`、`write`） | `cognito-user-pool` |
| 6 | `data` | 一張 DynamoDB table（PK、SK，PITR，CMK） | `dynamodb-table` |
| 7 | `iam` | API Lambda 的 execution role：這張 table 的讀寫、這個 secret 的讀取、CMK decrypt | `iam-role`、`iam-role-policy` |
| 8 | `api` | Lambda、HTTP API（JWT authorizer 指向 `auth` 的 issuer 與 client）、custom domain、`api` alias record、access log group、Lambda 錯誤與 API 5xx 告警 | `lambda-function`、`apigateway-http`、`log-group`、`route53-record`、`metric-alarm` |
| 9 | `web` | 前端 bucket（SSE-S3）、CloudFront（OAC、`spa_fallback`）、`app` alias record、可選的 CloudFront WAF（K14）、CloudFront log | `s3-bucket` 0.5.0、`cloudfront-distribution`、`route53-record`、`waf-web-acl` 0.2.0、`log-delivery` 0.2.0 |

- example6 照 `templates/project-infra` 的標準：只有樹 A，沒有 bridge。example6 沒有交給客戶自管的需求，跟 example4、example5 一樣。
- 所有 stack 只呼叫 module，S8 例外清單沒有 example6 的列。
- `web` 的 bucket policy 要 distribution ARN，distribution 又要 bucket 的 domain：兩者在同一個 stack，module 輸出是逐值相依，不會形成循環（未確認，I9 用 `terraform validate` 確認）。

### 8.2 SSM 合約（樹 A）

| key | 寫 | 讀 |
|---|---|---|
| `containerimage/api_repository_url` | `containerimage` | `api` |
| `foundation/kms_key_arn`、`alarm_topic_arn`、`api_secret_arn` | `foundation` | `data`、`iam`、`api` |
| `dns/zone_id`、`zone_name` | `dns` | `certificate`、`api`、`web` |
| `certificate/api_certificate_arn`、`web_certificate_arn` | `certificate` | `api`、`web` |
| `auth/issuer_url`、`spa_client_id`、`user_pool_arn` | `auth` | `api` |
| `data/table_name`、`table_arn` | `data` | `iam`、`api` |
| `iam/api_role_arn` | `iam` | `api` |

### 8.3 dev／sit 的預設規格

| 項目 | dev | sit |
|---|---|---|
| Lambda | arm64、512 MB、timeout 10 秒、reserved concurrency 10 | 同左，reserved concurrency 50 |
| API throttling | rate 50、burst 100 | rate 200、burst 400 |
| DynamoDB | on-demand、PITR 7 天、deletion protection 關 | on-demand、PITR 35 天、deletion protection 開 |
| Cognito | `ESSENTIALS`、MFA `OPTIONAL`、deletion protection 關 | 同左，deletion protection 開 |
| CloudFront | `PriceClass_200`、WAF 關 | 同左 |
| log 保存 | 30 天 | 90 天 |

### 8.4 文件

`infra/README.md`（短）、`infra/REFERENCE.md`、`infra/architecture.drawio.svg`，格式照 example5。根 README 的範本表加一列 example6。

## 9. 測試情境（TDD）

每個 module 用 `mock_provider "aws"`，至少要有：

| module | 正向 | 要被擋的 |
|---|---|---|
| `secrets-manager-secret` | 只有名稱；CMK 加 policy 加 rotation | `recovery_window_in_days = 0`；`Principal *` 沒有 condition 的 `Allow`；兩種 rotation 排程同時給；名稱尾巴像後綴 |
| `route53-zone` | public zone；private zone | 名稱尾巴帶 `.`；`vpc_ids` 格式錯 |
| `route53-record` | A alias；TXT 多值；CNAME | alias 加 `TXT`；`CNAME` 兩個值；`ttl` 0；沒有 `values` 也沒有 alias |
| `acm-certificate` | apex 加 wildcard SAN（確認驗證 record 去重）；`region = "us-east-1"` | 11 個名稱；wildcard 不在最左邊 |
| `cloudfront-distribution` | S3 origin 加 OAC 加 `spa_fallback`；custom origin 加 origin verify（plan 顯示 sensitive） | `aliases` 沒有憑證；憑證不是 us-east-1；behavior 指到不存在的 origin；origin verify 指到 S3 origin |
| `apigateway-http` | JWT route 加 public health route 加 custom domain | route 沒有 authorizer 也沒有 `public`；`allow_credentials` 配 `*`；authorizer key 不存在 |
| `cognito-user-pool` | SPA client 加 resource server scope | `http://` 非 localhost 的 callback；不存在的 scope；`domain_prefix` 含 `cognito` |
| `waf-web-acl` 0.2.0 | `scope = "CLOUDFRONT"` 時所有 resource 的 `region` 是 us-east-1；預設仍是 REGIONAL | `scope` 其他值 |
| `s3-bucket` 0.5.0 | 給 distribution ARN 時 policy 多一條；不給時 policy 跟 0.4.0 一樣 | ARN 不是 CloudFront distribution |
| `log-delivery` 0.2.0 | `region` 套到三種 resource | `region` 格式錯 |

範本 stack 的測試照 example5：每個 stack 的 `tests/` 用 mock 驗 SSM 讀寫、名稱與跨 stack 一致的值。

## 10. 成本估計（粗估，美元／月，未查證）

> 這一節的價格沒有逐項查過官方價目表，只能拿來判斷量級，不要當報價。實作 I10 時照 v8 §10 的做法查 Tokyo 價格並更新，來源寫進 §13。

| 項目 | dev 估計 | 說明 |
|---|---|---|
| Route 53 hosted zone | 0.5 | 每個 zone，查詢量另計 |
| ACM 公開憑證 | 0 | |
| Secrets Manager | 0.4／secret | 加 API 呼叫 |
| CloudFront | 接近 0 | 低流量時落在免費額度內 |
| CloudFront WAF（example2） | 約 10 起 | web ACL 加每條規則月費，加請求費 |
| API Gateway HTTP API | 接近 0 | 依請求數 |
| Cognito `ESSENTIALS` | 0 | 免費額度內的 MAU |
| Lambda、DynamoDB on-demand | 接近 0 | 依用量 |

example2 每個環境的增量主要是 CloudFront WAF；example6 在 WAF 關閉時，dev 閒置成本低於 5 美元。

## 11. 風險與 mock 驗不到的事

- **origin verify 換值會中斷**（§4.1）：要看 `alb` module 能不能同時收兩個值。
- **K8 的 Host 與 SNI 行為**：轉送 Host 時，CloudFront 用 Host 做 SNI，ALB 憑證要涵蓋 `api.<env>`；這點要在第一次 apply 時確認。
- **ALB WAF 的 rate limit 在 CDN 後面失準**（K9）：要在 ALB 層限流，之後可以用 `forwarded_ip_config` 讀 `X-Forwarded-For`，但這個 header 可以被偽造，要搭配 origin verify。這一版不改。
- **ALB SG 的 prefix list 配額**：CloudFront origin-facing prefix list 在 SG 裡佔很多條規則的額度（example2 network 的 description 已經提到），加上辦公室 CIDR 可能超過 60 條的預設上限。要先申請提高配額，或拿掉辦公室 CIDR。
- **DNS 委派是人工步驟**：委派錯誤時 `certificate` 會 timeout（§7.2）。
- **Cognito `COGNITO_DEFAULT` 的寄信上限**（K11）：sit 做大量註冊測試時會撞到。
- **HTTP API 的 access log 權限**：§5.6 標未確認。
- **`moved` 搬 for_each resource 進 module**：§6 標未確認。
- **CloudFront log 的跨 region delivery**：delivery 在 us-east-1、bucket 在 ap-northeast-1，要在第一次 apply 時確認可行。
- **destroy**：zone 裡還有 record 時刪不掉；ACM 憑證還被 ALB 或 CloudFront 用時刪不掉；Cognito 與 DynamoDB 開了 deletion protection。REFERENCE〈destroy 之前〉要列。

## 12. Phase

| Phase | 內容 | 依賴 |
|---|---|---|
| I0 | 這份設計與實作流程 | — |
| I1 | `secrets-manager-secret`；6 處搬遷、S8 例外清單、標準指南（§6） | I0 |
| I2 | `route53-zone`、`route53-record`、`acm-certificate` | I0 |
| I3 | `waf-web-acl` 0.2.0、`s3-bucket` 0.5.0、`log-delivery` 0.2.0 | I0 |
| I4 | `apigateway-http`、`cognito-user-pool` | I0 |
| I5 | `cloudfront-distribution` | I0 |
| I6 | example2 `dns`、`certificate`、`bridge`、`loadbalancer` HTTPS | I2 發版 |
| I7 | example2 `edge`、`network` 與 `application` 的 tfvars、README、REFERENCE、架構圖 | I3、I5、I6 |
| I8 | example6 骨架與 `containerimage`、`foundation`、`dns`、`certificate`、`data`、`iam` | I1、I2 發版 |
| I9 | example6 `auth`、`api`、`web` | I3、I4、I5、I8 |
| I10 | example6 README、REFERENCE、架構圖；根 README（80 個 module）；全量驗證；§10 價格查證；§14 | I7、I9 |

I1–I5 的目錄互不重疊，可以在各自的 worktree 平行做。I1 的範本搬遷動到 example2，所以 I6 要等 I1 合併。

## 13. 來源

- aws provider 6.70.0 schema：本機 `terraform providers schema -json`（2026-10-28），§2 第 1–5 點、§5 的 resource 與屬性。
- example2 現況：`templates/example2/infra/terraform/loadbalancer/variables.tf`（`certificate_arn` 為 `null` 時只開 HTTP）、`network/variables.tf`（`alb_ingress` 與 prefix list 配額）、`application/variables.tf`（`trusted_proxies`）。
- 範本的 secret：`templates/*/infra/terraform/foundation/secrets.tf`、`templates/project-infra/infra/terraform/agent/knowledge-bases.tf`；S8 例外清單：`scripts/validate.sh` 的 `s8_allowed`。
- 未查證、實作時補來源：HTTP API 與 WAF 的支援範圍（§2 第 6 點）、CloudFront 轉送 Host 時的 SNI 行為（K8）、Cognito `COGNITO_DEFAULT` 寄信上限（K11）、§10 的價格。

## 14. 實作後的變更

（實作時填。）
