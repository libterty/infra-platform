# example2 雲端驗證 runbook（v9 的 CDN 與邊緣層）

## 結論

這份 runbook 列出 `templates/example2` 第一次在真實 AWS 帳號 apply 時，v9 加進來的部分要逐項確認的事。照做完，就能把 design v9 §11 與 example2 README〈已知限制〉裡跟 CloudFront、DNS、憑證有關的推論，改成有證據的結論。

- 範圍只有 v9 加的東西：`dns`、`certificate`、`edge` 三個新 stack，CloudFront 擋在 ALB 前面、ALB 改 HTTPS、origin verify header、ALB security group 放 CloudFront prefix list、`application` 的 `trusted_proxies`、`foundation` 的 secret 改用 `secrets-manager-secret` 並用 `moved` 搬進 module。共 13 項。
- v9 之前就有的 example2 內容（IAM 形狀、ALB access log、WAF logging 權限、AgentCore、no-NAT、S3 通知、autoscaling、跟應用程式的約定）不在本文。example2 的 REFERENCE.md 沒有〈雲端整合待驗證〉清單，那些項目只列在 README〈已知限制〉與 REFERENCE〈已知限制的細節〉，追蹤在 `docs/design/v2/design-docs.md` §5.8、§5.10。
- 每一項都有：前提（要 apply 哪些 stack、tfvars 怎麼設）、指令、預期結果、結果紀錄。
- 指令預設都是唯讀。會改變狀態的指令標【寫入】，只在 `dev` 執行。
- 這份文件的指令都**沒有實際跑過**，名稱與數值都從程式碼推出來，出處寫在每段的「名稱怎麼來的」。標「推測」的是 repo 以外的慣例（AWS 的預設行為或命名），執行時以實際輸出為準。
- 從程式碼就看得出來、第一次驗證很可能卡住的三件事，先講：
  1. **`dev` 的 ALB security group 很可能超過規則數配額**：CloudFront origin-facing prefix list 依它的 `MaxEntries` 計入配額，`dev` 另外有辦公室 CIDR 的 443 與 80 兩條（`network/security-groups.tf:17-38`）。預設上限 60 條，`MaxEntries` 接近 60 時 `network` apply 會失敗。第 4 項要在 apply `network` **之前**做。
  2. **prefix list 的 ID 沒查證**：`network/envs/*.tfvars` 的 `pl-58a04531` 是 ap-northeast-1 的佔位值，design §14 寫明沒有查證。ID 不對時 `network` apply 失敗，或 ALB 擋掉 CloudFront（全部 504）。
  3. **換 origin verify 的值一定會中斷**：`alb` module 的 listener rule 只放一個值（`modules/alb/main.tf:180`），design §14 已確認。第 11 項只量中斷多久，不是驗會不會中斷。

## 範圍

涵蓋：

| 編號 | 項目 | 來源 |
|---|---|---|
| 1 | hosted zone 與上層網域的 NS 委派 | design §7.2、§11「DNS 委派是人工步驟」；REFERENCE〈第一次 apply〉 |
| 2 | 兩張 ACM 憑證與 `bridge` 的 region 檢查 | design §2 第 1、5 點、§7.1、§14 `acm-certificate` |
| 3 | ALB 的 HTTPS listener 與 HTTP 轉址 | design K7、§7.1 |
| 4 | ALB security group 的 prefix list 與配額 | design §11「ALB SG 的 prefix list 配額」、§14 `network` |
| 5 | CloudFront 回源、Host 與 SNI、DNS record | design K8、§11「K8 的 Host 與 SNI 行為」 |
| 6 | origin verify header 的保護 | design §2 第 2 點、§4.1 |
| 7 | CloudFront WAF 與 ALB WAF 的 rate limit | design K9、§11「ALB WAF 的 rate limit 在 CDN 後面失準」 |
| 8 | CloudFront log 跨 region 送到 bucket | design §2 第 7 點、§11「CloudFront log 的跨 region delivery」 |
| 9 | `trusted_proxies = "vpc_and_cdn"` | design §7.1 |
| 10 | 回源 read timeout 60 秒與串流 | design §14 example2；REFERENCE〈已知限制的細節〉 |
| 11 | 換 origin verify 的值 | design §4.1、§11 第 1 點、§14 查證結果；REFERENCE〈換 origin verify 的值〉 |
| 12 | secret 用 `moved` 搬進 module | design §6、§11「`moved` 搬 for_each resource 進 module」 |
| 13 | destroy 的阻擋點 | design §11「destroy」；REFERENCE〈destroy 之前〉 |

design §11 各點的去處：

| §11 | 內容 | 在本文 |
|---|---|---|
| 1 | origin verify 換值會中斷（`alb` 能不能同時收兩個值） | 第 11 項；能不能收兩個值已由 §14 與 `modules/alb/main.tf:180` 確認「不能」 |
| 2 | example6 繞過 WAF | 不在本文：example6 |
| 3 | K8 的 Host 與 SNI，ALB 憑證要涵蓋 `api.<env>` | 第 5 項（憑證內容在第 2 項） |
| 4 | ALB WAF 的 rate limit 在 CDN 後面失準 | 第 7 項 |
| 5 | ALB SG 的 prefix list 配額（60 條）與辦公室 CIDR | 第 4 項 |
| 6 | DNS 委派是人工步驟 | 第 1 項 |
| 7 | Cognito `COGNITO_DEFAULT` 寄信上限 | 不在本文：example6 |
| 8 | HTTP API access log 權限 | 不在本文：example6；§14 已查證 |
| 9 | `moved` 搬 for_each resource 進 module | 第 12 項。example2 是每個 key 各寫一個 `moved`（`foundation/secrets.tf:27-35`），不是整組搬；整組搬只有 project-infra 的 `kb_db`，§14 已確認不行 |
| 10 | CloudFront log 的跨 region delivery | 第 8 項 |
| 11 | destroy（zone、ACM 憑證、Cognito、DynamoDB） | 第 13 項，只含 example2 的 zone、憑證、distribution、bucket、secret；Cognito 與 DynamoDB 是 example6 |

不涵蓋：README〈已知限制〉裡 v9 之前就有的項目（見〈結論〉第二點）。

## 需要的權限與工具

工具：

- AWS CLI v2、`jq`、Terraform（apply 用）。
- `dig`、`curl`、`openssl`（第 1、3、5、6、7、10、11 項）。
- 一台在 `dev` 辦公室 CIDR 裡的機器（`network/envs/dev.tfvars:22`，佔位 `203.0.113.0/24`），用來直接連 ALB；一台**不在**任何 allowlist 裡的機器，用來測 rate limit（第 7 項）。

身分：

| 用途 | 身分 | 依據 |
|---|---|---|
| apply 各 stack | 各 stack 的 apply 身分（`deploy_role_arn` 或呼叫者自己） | 各 stack 的 `providers.tf` |
| apply `certificate`、`edge` | 同上，**而且要能在 us-east-1 建資源**：ACM、WAF、CloudWatch Logs（WAF log group、log delivery）。組織有限制 region 的 SCP 時要先放行 us-east-1 的這幾個服務（推測：SCP 是組織自己的設定，repo 裡沒有） | `certificate/certificates.tf:13-16`、`edge/waf.tf:6`、`edge/logs.tf:12` |
| 執行本文的唯讀指令 | 有下面唯讀權限的任何身分 | 本文 |

驗證身分要的 AWS 權限（唯讀）：`sts:GetCallerIdentity`、`ssm:GetParameter`、`route53:GetHostedZone`、`route53:ListResourceRecordSets`、`acm:DescribeCertificate`、`acm:ListCertificates`、`elasticloadbalancing:Describe*`、`ec2:DescribeManagedPrefixLists`、`ec2:GetManagedPrefixListEntries`、`ec2:DescribeSecurityGroupRules`、`servicequotas:GetServiceQuota`、`cloudfront:GetDistribution`、`cloudfront:GetDistributionConfig`、`wafv2:ListWebACLs`、`wafv2:GetWebACL`、`wafv2:GetWebACLForResource`、`wafv2:GetLoggingConfiguration`、`logs:FilterLogEvents`、`logs:DescribeDeliverySources`、`logs:DescribeDeliveryDestinations`、`logs:DescribeDeliveries`、`s3:ListBucket`、`s3:GetBucketLocation`、`s3:GetBucketPolicy`、`s3:GetEncryptionConfiguration`、`ecs:DescribeServices`、`ecs:DescribeTaskDefinition`、`secretsmanager:DescribeSecret`、`secretsmanager:ListSecretVersionIds`。**不需要** `secretsmanager:GetSecretValue`，本文不讀 secret 的值。

【寫入】要另外的權限：`servicequotas:RequestServiceQuotaIncrease`（第 4 項，配額不夠時）、`s3:DeleteObject`（第 13 項清空 bucket）。

網路：

- 第 1 項的 `dig` 要能查公開 DNS。
- 第 3、6 項直接連 ALB，只有 `dev` 的辦公室 CIDR 進得去。`sit` 的 ALB 只開 CloudFront prefix list（`network/envs/sit.tfvars:19`），從外面直接連會 timeout，這本身就是 `sit` 的預期結果。

## 共用變數

每次開新的 shell 先跑這段。`<project>`、`<env>` 換成 tfvars 的值（`dev` 或 `sit`）。

```bash
export AWS_REGION=ap-northeast-1          # common.tf:24，aws_region 預設值；改過就跟著改
P=<project>                               # tfvars 的 project
E=<env>                                   # dev 或 sit
HDR=X-Origin-Verify                       # loadbalancer、edge 的 origin_verify_header_name
ssm() { aws ssm get-parameter --name "$1" --query Parameter.Value --output text; }

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ZONE_ID=$(ssm "/$P/$E/dns/zone_id")
ZONE=$(ssm "/$P/$E/dns/zone_name")                        # 例如 dev.example.com
API="api.$ZONE"
ORIGIN="origin-api.$ZONE"
ALB_CERT=$(ssm "/$P/$E/certificate/alb_certificate_arn")
CF_CERT=$(ssm "/$P/$E/certificate/cloudfront_certificate_arn")
ALB_SG=$(ssm "/$P-shared/$E/infra/alb_sg_id")
LB_ARN=$(aws elbv2 describe-load-balancers --names "$P-$E-alb" --query 'LoadBalancers[0].LoadBalancerArn' --output text)
DIST_ID=$(ssm "/$P/$E/edge/distribution_id")
CF_DOMAIN=$(ssm "/$P/$E/edge/domain_name")
```

還沒 apply 到的 stack，對應的變數會是空的或報 `ParameterNotFound`，先忽略，做到那一項再重跑。

名稱怎麼來的：

- SSM 前綴：`common.tf:50` 的 `ssm_prefix = "/${var.project}/${var.env}"`、`common.tf:54` 的 `shared_ssm_prefix = "/${var.project}-shared/${var.env}"`；`ssm-publish` 寫成 `"${var.ssm_prefix}/${var.stack}/${each.key}"`（`modules/ssm-publish/main.tf:4`）。
- key：`dns/ssm-outputs.tf:3-4,8`、`certificate/ssm-outputs.tf:3-4`、`edge/ssm-outputs.tf:4-5`、`loadbalancer/ssm-outputs.tf:9-10`；`alb_sg_id` 由 `network/ssm-outputs.tf:5` 發布、`bridge/ssm-outputs.tf:11` 轉寫到樹 B。
- ALB 名稱：`loadbalancer/alb.tf:2` 的 `"${local.name_prefix}-alb"`，`common.tf:47` 的 `name_prefix = "${var.project}-${var.env}"`。
- header 名稱：`loadbalancer/envs/dev.tfvars:8`、`edge/envs/dev.tfvars:9`（`sit` 同一行）。
- `api`、`origin-api` 兩個名稱：`edge/distribution.tf:4-5`、`certificate/certificates.tf:8-9`。

## 執行順序

順序照 `stacks.sh:8` 的 `ORDER`：`containerimage foundation dns certificate network database iam bridge loadbalancer edge agent application operation postdeploy`，以及 README〈第一次 apply〉。建議一個 stack 一個 stack apply，每個先跑 `--dry-run` 看一次指令，不要直接 `all apply`，才能在中間做驗證。

| 階段 | 做什麼 | 做完接著驗 |
|---|---|---|
| 0 | 照 README〈複製出去之後要改什麼〉換佔位值，v9 相關的是：`dns` 的 `zone_name`、`loadbalancer` 的 `origin_verify_host_headers`（要等於 `api.<zone>`）、`network` 的 `alb_ingress`（prefix list ID、辦公室 CIDR）、兩邊的 `rate_limit_allowlist_cidrs`；`export TF_VAR_origin_verify_header_value=...`；api 等映像推上 ECR | 第 4 項的「apply 前」部分 |
| A | `containerimage`、`foundation` | 第 12 項（有舊版 state 時，`foundation` 要在 apply 前先 plan） |
| B | `dns` | 第 1 項前半 |
| C | 人工在上層網域加 NS 委派 | 第 1 項後半 |
| D | `certificate` | 第 2 項 |
| E | `network`、`database`、`iam`、`bridge` | 第 4 項的「apply 後」部分、第 2 項的 `bridge` 部分 |
| F | `loadbalancer` | 第 3 項 |
| G | `edge` | 第 5 項前半、第 6、7、8 項的設定部分 |
| H | `agent`、`application`（api 要真的跑起來）、`operation`、`postdeploy` | 第 5 項後半、第 6、7、8 項的流量部分、第 9、10 項 |
| I | 換 origin verify 的值 | 第 11 項 |
| J | 只在 `dev`、最後做：`./stacks.sh dev all destroy` | 第 13 項 |

`edge` 一定要在 `loadbalancer` 之後：它讀 `loadbalancer/alb_dns_name`、`alb_zone_id`（`edge/ssm-inputs.tf:3-6`）。`certificate` 一定要在委派生效之後，不然會等滿 45 分鐘才失敗（`modules/acm-certificate/variables.tf:73`）。

---

## 1. hosted zone 與 NS 委派

**前提**

- 階段 B 完成：`./stacks.sh <env> dns apply`。
- `dns/envs/<env>.tfvars:7` 的 `zone_name` 已經換成自己網域底下的子網域。

**指令**

```bash
aws route53 get-hosted-zone --id "$ZONE_ID" \
  --query '{name:HostedZone.Name,private:HostedZone.Config.PrivateZone,ns:DelegationSet.NameServers}'
ssm "/$P/$E/dns/name_servers"
./stacks.sh "$E" dns output          # 在 infra/terraform 底下跑；只讀 state
```

階段 C：在上層網域加一筆 NS record（名稱 `<zone>`，值是上面 4 個 name server），然後：

```bash
dig NS "$ZONE" +short | sort
dig NS "$ZONE" +trace | tail -8      # 看上層網域的權威 server 回的是哪 4 個
dig SOA "$ZONE" +short
```

名稱怎麼來的：zone 名稱是 `var.zone_name`（`dns/zone.tf:6`）、comment 是 `"${local.name_prefix} public zone"`（`dns/zone.tf:7`）；`name_servers` 是 StringList（`dns/ssm-outputs.tf:7-9`），也是 terraform output（`dns/outputs.tf:2-4`）。

**預期結果**

- zone 名稱是 `<zone>.`，`private` 是 `false`，有 4 個 name server。
- SSM 的 `name_servers` 與 `dns output` 跟 `DelegationSet.NameServers` 是同樣 4 個。
- 委派之後 `dig NS` 回的就是這 4 個（順序可能不同），`+trace` 的最後一段由上層網域交給這 4 個；`dig SOA` 有回應。
- 記下：從加 NS record 到 `dig` 查得到花了多久（上層網域的 NS TTL 決定，推測）。

委派做錯時，`certificate` 會等滿 45 分鐘才失敗。如果第一次真的遇到，把錯誤訊息貼在備註，確認看得出是在等驗證（README〈第一次 apply〉第 3 步的說法）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／委派生效花了 ______

## 2. 兩張 ACM 憑證

**前提**

- 階段 D 完成：`certificate` apply 成功（會等到兩張都簽發）。
- `certificate` stack 只有一個 provider（`certificate/providers.tf:12-27`，region 是 `aws_region`），CloudFront 憑證靠 module 的 `region = "us-east-1"` 建在 us-east-1（`certificate/certificates.tf:15`、`:35`；`modules/acm-certificate/main.tf:12`）。這就是 design §2 第 1 點「不用 provider alias」要在真實帳號確認的事。

**指令**

```bash
aws acm describe-certificate --certificate-arn "$ALB_CERT" \
  --query 'Certificate.{status:Status,domain:DomainName,sans:SubjectAlternativeNames,key:KeyAlgorithm,inUse:InUseBy,validation:DomainValidationOptions[].[DomainName,ValidationStatus,ResourceRecord.Name]}'
aws acm describe-certificate --region us-east-1 --certificate-arn "$CF_CERT" \
  --query 'Certificate.{status:Status,domain:DomainName,sans:SubjectAlternativeNames,key:KeyAlgorithm,inUse:InUseBy,validation:DomainValidationOptions[].[DomainName,ValidationStatus,ResourceRecord.Name]}'

# 驗證 record：api 的那筆兩張憑證共用
aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" \
  --query "ResourceRecordSets[?Type=='CNAME'].[Name,ResourceRecords[0].Value]" --output text

# 再 plan 一次：共用的驗證 record 由兩個 module 管，不應該每次都有變更
./stacks.sh "$E" certificate plan -- -detailed-exitcode; echo "exit=$?"
```

階段 E 的 `bridge` apply 之後：

```bash
ssm "/$P-shared/$E/infra/alb_certificate_arn"
ssm "/$P-shared/$E/infra/cloudfront_certificate_arn"
ssm "/$P-shared/$E/infra/zone_id"
ssm "/$P-shared/$E/infra/zone_name"
```

名稱怎麼來的：ALB 憑證的名稱 `api.<zone>`、SAN `origin-api.<zone>`（`certificate/certificates.tf:7-10`）；CloudFront 憑證 `api.<zone>`（`certificate/certificates.tf:13-16`）；驗證 record 的 key 去掉 `*.`，`allow_overwrite = true`（`modules/acm-certificate/main.tf:4`、`:27-39`）；`bridge` 的 region 檢查（`bridge/guards.tf:7-10`、`:18-21`、`:53-60`）；樹 B 的四個 key（`bridge/ssm-outputs.tf:27-30`）。

**預期結果**

- ALB 憑證：ARN 是 `arn:aws:acm:<aws_region>:...`，`ISSUED`，domain `api.<zone>`，SAN 有 `api.<zone>` 與 `origin-api.<zone>`，`RSA_2048`。
- CloudFront 憑證：ARN 是 `arn:aws:acm:us-east-1:...`，`ISSUED`，domain `api.<zone>`。
- 兩張憑證 `api.<zone>` 的 `ResourceRecord.Name` 相同；zone 裡剛好兩筆驗證 CNAME（`api` 共用一筆、`origin-api` 一筆）。
- `certificate plan` 的 `exit=0`（沒有變更）。`exit=2` 表示共用 record 在兩個 module 之間互相覆蓋，把 plan 貼在備註。
- `bridge` apply 成功（region 檢查通過），樹 B 的 4 個值等於樹 A。
- `InUseBy`：`loadbalancer` apply 後 ALB 憑證有 ALB 的 ARN；`edge` apply 後 CloudFront 憑證有 distribution 的 ARN。

注意：兩張憑證共用的驗證 record 由兩個 module address 各管一份。只 destroy 或重建其中一張時，Terraform 會刪掉這筆 record，另一張憑證到期前的自動續約就驗不到。之後改憑證名稱時要先看 plan 有沒有刪這筆 record。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／簽發花了 ______

## 3. ALB 的 HTTPS listener 與 HTTP 轉址

**前提**

- 階段 F 完成：`loadbalancer` apply 成功。
- `loadbalancer/envs/<env>.tfvars:9` 的 `origin_verify_host_headers` 已經改成 `["api.<zone>"]`。
- 直接連 ALB 的指令要在 `dev` 的辦公室 CIDR 裡跑。

**指令**

```bash
aws elbv2 describe-listeners --load-balancer-arn "$LB_ARN" \
  --query 'Listeners[].{port:Port,proto:Protocol,policy:SslPolicy,cert:Certificates[0].CertificateArn,action:DefaultActions[0].Type,redirect:DefaultActions[0].RedirectConfig,fixed:DefaultActions[0].FixedResponseConfig.StatusCode}'

HTTPS_L=$(aws elbv2 describe-listeners --load-balancer-arn "$LB_ARN" --query 'Listeners[?Port==`443`].ListenerArn' --output text)
# 只印條件的種類與 header 名稱，不要印 HttpHeaderConfig.Values：那是 origin verify 的值
aws elbv2 describe-rules --listener-arn "$HTTPS_L" \
  --query 'Rules[?Priority!=`default`].{p:Priority,fields:Conditions[].Field,host:Conditions[?Field==`host-header`]|[0].HostHeaderConfig.Values,header:Conditions[?Field==`http-header`]|[0].HttpHeaderConfig.HttpHeaderName}' --output json

# dev，辦公室 CIDR 裡
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' "http://$ORIGIN/api/quota"
echo | openssl s_client -connect "$ORIGIN:443" -servername "$ORIGIN" 2>/dev/null | openssl x509 -noout -subject -ext subjectAltName
echo | openssl s_client -connect "$ORIGIN:443" -servername "$API" 2>/dev/null | openssl x509 -noout -subject -ext subjectAltName
```

`$ORIGIN` 要等階段 G 的 `edge` 建好 `origin-api` record 才解得到。在那之前，把 `$ORIGIN` 換成 `$(ssm "/$P/$E/loadbalancer/alb_dns_name")`，`openssl` 加 `-servername` 照舊。

名稱怎麼來的：HTTPS listener 443、`ELBSecurityPolicy-TLS13-1-2-2021-06`、預設回 404（`modules/alb/main.tf:22-42`）；HTTP:80 有憑證時轉到 443、`HTTP_301`（`modules/alb/main.tf:51-79`）；rule 掛在 HTTPS listener（`modules/alb/main.tf:5`）；rule 的 priority、path、host、`require_origin_verify`（`loadbalancer/alb.tf:6-32`）；條件（`modules/alb/main.tf:157-182`）。

**預期結果**

- 兩個 listener：443 `HTTPS`，policy `ELBSecurityPolicy-TLS13-1-2-2021-06`，憑證是 `$ALB_CERT`，預設 `fixed-response` 404；80 `HTTP`，`redirect` 到 `HTTPS` 443、`HTTP_301`。
- 443 上的 rule：10、20、30 各有 `host-header`（`api.<zone>`）、`path-pattern`、`http-header`（名稱 `X-Origin-Verify`）；`dev` 另有 100（只有 `path-pattern`，`/dev/page`）。
- `curl http://...` 回 `301`，`redirect_url` 是 `https://...`。
- 兩次 `openssl` 都拿到同一張憑證，SAN 有 `api.<zone>` 與 `origin-api.<zone>`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 4. ALB security group 的 prefix list 與配額

**前提**

- 「apply 前」部分在階段 0 做，`network` 還沒 apply。
- `network` 只在 443 放 prefix list，CIDR 開 443 與 80（`network/security-groups.tf:17`、`:24-38`）。`dev` 有一個辦公室 CIDR（`network/envs/dev.tfvars:20-23`），`sit` 沒有（`network/envs/sit.tfvars:19`）。

**指令**

apply 前：

```bash
# 1. ID 對不對（design §14：pl-58a04531 沒有查證）
aws ec2 describe-managed-prefix-lists --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing \
  --query 'PrefixLists[].[PrefixListId,MaxEntries,AddressFamily]' --output text
grep -n prefix_list_ids network/envs/"$E".tfvars

# 2. 目前的配額（quota code 是 AWS 的命名，推測；不對就用 list-service-quotas 找 "rules per security group"）
aws service-quotas get-service-quota --service-code vpc --quota-code L-0EA8095F \
  --query 'Quota.[QuotaName,Value]' --output text
```

算法：`dev` 的 inbound 規則數 = `MaxEntries`（443 一份）+ 2（辦公室 CIDR 的 443 與 80）；`sit` = `MaxEntries`。大於配額就先申請提高：

```bash
# 【寫入】只在需要時；值依上面的計算
aws service-quotas request-service-quota-increase --service-code vpc --quota-code L-0EA8095F --desired-value <新值>
```

這個配額乘上每個網卡的 security group 數不能超過 1000（REFERENCE〈已知限制的細節〉）。

apply `network` 後：

```bash
aws ec2 describe-security-group-rules --filters Name=group-id,Values="$ALB_SG" \
  --query 'SecurityGroupRules[].[IsEgress,FromPort,PrefixListId,CidrIpv4,ReferencedGroupInfo.GroupId,Description]' --output table
```

名稱怎麼來的：prefix list 名稱 `com.amazonaws.global.cloudfront.origin-facing`（`network/envs/dev.tfvars:16` 的註解、`application/environment.tf:9`）；ALB SG 名稱 `<project>-<env>-alb`（`network/security-groups.tf:5`）；規則的 key 與描述（`network/security-groups.tf:27-37`）；egress 到 `app` 的 `app_port`（`network/security-groups.tf:44`）。

**預期結果**

- 查到的 prefix list ID 等於 tfvars 的值；不等就改 tfvars（兩份都要改）再 apply。記下 `MaxEntries`。
- 配額 ≥ 上面算出的規則數；`network` apply 沒有 `RulesPerSecurityGroupLimitExceeded`。
- ALB SG 的 inbound：443 一條 prefix list；`dev` 另有辦公室 CIDR 的 443 與 80；沒有 prefix list 的 80。outbound 只有一條到 `app` SG 的 `app_port`。
- 記下最後用的配額值，寫進 REFERENCE 當參考。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／`MaxEntries` ______、配額 ______

## 5. CloudFront 回源、Host 與 SNI、DNS record

**前提**

- 階段 G 完成：`edge` apply 成功（會等 distribution 部署完）。
- 「經 CloudFront 打到 api」的部分要等階段 H：`application` 已 apply，api 的 task 是 healthy。
- design K8 與 §14：CloudFront 轉送 viewer 的 Host（`api.<zone>`）時，用它做 SNI 與憑證比對，所以 ALB 憑證要有 `api.<zone>`（第 2 項已確認憑證內容）。這一項確認實際行為。

**指令**

```bash
# distribution 設定
aws cloudfront get-distribution --id "$DIST_ID" --query 'Distribution.{status:Status,domain:DomainName,aliases:DistributionConfig.Aliases.Items,cert:DistributionConfig.ViewerCertificate.ACMCertificateArn,minTls:DistributionConfig.ViewerCertificate.MinimumProtocolVersion,sni:DistributionConfig.ViewerCertificate.SSLSupportMethod,waf:DistributionConfig.WebACLId,price:DistributionConfig.PriceClass,http:DistributionConfig.HttpVersion,ipv6:DistributionConfig.IsIPV6Enabled}'

# origin：只印 header 名稱，不要印 CustomHeaders 的 HeaderValue
aws cloudfront get-distribution-config --id "$DIST_ID" \
  --query 'DistributionConfig.Origins.Items[].{id:Id,domain:DomainName,proto:CustomOriginConfig.OriginProtocolPolicy,ssl:CustomOriginConfig.OriginSslProtocols.Items,read:CustomOriginConfig.OriginReadTimeout,keepalive:CustomOriginConfig.OriginKeepaliveTimeout,headers:CustomHeaders.Items[].HeaderName}'
aws cloudfront get-distribution-config --id "$DIST_ID" \
  --query 'DistributionConfig.DefaultCacheBehavior.{viewer:ViewerProtocolPolicy,methods:AllowedMethods.Items,cache:CachePolicyId,originReq:OriginRequestPolicyId,respHeaders:ResponseHeadersPolicyId}'

# DNS record
aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" \
  --query "ResourceRecordSets[?Name=='$API.' || Name=='$ORIGIN.'].[Name,Type,AliasTarget.DNSName]" --output text
dig +short A "$API"; dig +short AAAA "$API"; dig +short A "$ORIGIN"

# 經 CloudFront 打 api（任何地方）
curl -s -o /dev/null -w '%{http_code}\n' "http://$API/api/quota"
curl -s -D - -o /dev/null "https://$API/api/quota" | grep -iE '^HTTP|^x-cache|^via|^server'
curl -s -D - -o /dev/null "https://$API/not-a-route" | grep -iE '^HTTP|^x-cache'
```

名稱怎麼來的：distribution 的 `name` 與 `comment` 是 `<project>-<env>-api`（`edge/distribution.tf:8`；`modules/cloudfront-distribution/main.tf:56`、`:147`）；alias、憑證、WAF、price class、origin 與 `read_timeout`、behavior（`edge/distribution.tf:7-30`）；`https-only`、`TLSv1.2`、`redirect-to-https`、`TLSv1.2_2021`、`sni-only`、`http2and3`、IPv6（`modules/cloudfront-distribution/main.tf:61-62`、`:72-81`、`:98`、`:140-145`）；response headers 預設 `Managed-SecurityHeadersPolicy`（`modules/cloudfront-distribution/variables.tf:153`）；record：`api` 的 A 與 AAAA 指 CloudFront、`origin-api` 的 A 指 ALB（`edge/records.tf:4-19`）。

**預期結果**

- `status` 是 `Deployed`；aliases 只有 `api.<zone>`；憑證是 `$CF_CERT`；`TLSv1.2_2021`、`sni-only`；`waf` 是第 7 項的 CloudFront web ACL ARN；`PriceClass_200`；`http2and3`；IPv6 `true`。
- 只有一個 origin `alb`：domain `origin-api.<zone>`，`https-only`，`TLSv1.2`，read 60、keepalive 5，headers 只有 `X-Origin-Verify`。
- 預設 behavior：`redirect-to-https`，7 種 method，cache、origin request、response headers 三個 policy 都有 ID（`Managed-CachingDisabled`、`Managed-AllViewer`、`Managed-SecurityHeadersPolicy`）。
- record：`api.<zone>.` 的 A 與 AAAA 指 `$CF_DOMAIN`；`origin-api.<zone>.` 的 A 指 ALB（Route 53 可能在前面加 `dualstack.`，推測）。`dig` 都有回位址。
- `http://` 回 `301`。
- `https://$API/api/quota` 回的是 api 的回應（狀態碼依應用程式而定，例如 200 或 401），**不是** 502，也不是 ALB 的 404。
- `/not-a-route` 回 404（ALB listener 的預設回應，`x-cache` 是 `Error from cloudfront`，推測）。

判讀：

| 看到 | 代表 |
|---|---|
| 502 | CloudFront 跟 ALB 的 TLS 沒過，多半是 Host 與憑證對不上（K8 不成立）或 SG 擋住。記下回應 body 與 `x-cache` |
| 504 | 連不到 ALB，多半是第 4 項的 prefix list 不對 |
| 404（`/api/quota`） | 到了 ALB 但 rule 沒中：Host 沒轉送（不是 `api.<zone>`），或 header 值兩邊不一致（第 6、11 項） |

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／`/api/quota` 的狀態碼 ______

## 6. origin verify header 的保護

**前提**

- 階段 G、H 完成。
- 值只從 `TF_VAR_origin_verify_header_value` 給，兩個 stack 的變數都是 `sensitive`（`loadbalancer/variables.tf:41-50`、`edge/variables.tf:11-20`），module 也是（`modules/alb/variables.tf:265-270`）。
- design §2 第 2 點：CloudFront 的 `custom_header.value` 在 provider schema 沒有標 sensitive，靠 module 的 sensitive 變數遮住 plan；state 仍是明文（§4.1 已接受）。

**指令**

```bash
# 1. plan 不會印出值（在 infra/terraform 底下跑）
./stacks.sh "$E" edge plan -- -no-color > /tmp/edge-plan.txt 2>&1
./stacks.sh "$E" loadbalancer plan -- -no-color > /tmp/lb-plan.txt 2>&1
grep -c -F "$TF_VAR_origin_verify_header_value" /tmp/edge-plan.txt /tmp/lb-plan.txt
rm /tmp/edge-plan.txt /tmp/lb-plan.txt

# 2. 不帶 header、帶錯的 header 直接打 ALB（dev，辦公室 CIDR 裡）
ALB_IP=$(dig +short A "$ORIGIN" | head -1)
curl -s -o /dev/null -w '%{http_code}\n' "https://$API/api/quota" --resolve "$API:443:$ALB_IP"
curl -s -o /dev/null -w '%{http_code}\n' "https://$API/api/quota" --resolve "$API:443:$ALB_IP" -H "$HDR: wrong-value-0000000"
curl -s -o /dev/null -w '%{http_code}\n' "https://$ORIGIN/dev/page"     # 只有 dev 有這條 rule

# 3. sit 從外面直接連 ALB：應該 timeout
curl -s -m 10 -o /dev/null -w '%{http_code}\n' "https://$ORIGIN/api/quota" || echo "timeout（預期）"

# 4. WAF log 把 header 遮掉：ALB WAF 收到 CloudFront 加的 header；edge WAF 只會在 client 自己帶時看到
curl -s -o /dev/null "https://$API/api/quota" -H "$HDR: client-sent-value-000"
aws logs filter-log-events --log-group-name "aws-waf-logs-$P-$E-alb" --limit 20 --query 'events[].message' --output text \
  | jq -c '.httpRequest.headers[]? | select(.name | ascii_downcase == "x-origin-verify")' | sort -u
aws logs filter-log-events --region us-east-1 --log-group-name "aws-waf-logs-$P-$E-api-edge" --limit 20 --query 'events[].message' --output text \
  | jq -c '.httpRequest.headers[]? | select(.name | ascii_downcase == "x-origin-verify")' | sort -u
aws wafv2 get-logging-configuration --region us-east-1 \
  --resource-arn "$(aws cloudfront get-distribution --id "$DIST_ID" --query Distribution.DistributionConfig.WebACLId --output text)" \
  --query 'LoggingConfiguration.RedactedFields'

# 5. state bucket 有加密（值以明文存在 loadbalancer 與 edge 的 state）
aws s3api get-bucket-encryption --bucket <state-bucket> --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault'
```

`--resolve` 讓 `curl` 把 `api.<zone>` 直接連到 ALB 的位址，SNI 與 Host 都是 `api.<zone>`，模擬 CloudFront 的請求，只是少了正確的 header。

名稱怎麼來的：WAF log group 是 `"aws-waf-logs-${var.name}"`（`modules/waf-web-acl/main.tf:20`），ALB WAF 的 `name` 是 `<project>-<env>-alb`（`loadbalancer/waf.tf:32`、`loadbalancer/alb.tf:2`），edge WAF 是 `<project>-<env>-api-edge`（`edge/waf.tf:5`），CloudFront 的 log group 在 us-east-1（`modules/waf-web-acl/main.tf:23`、`:261`）；遮蔽的 header 是 `authorization`、`cookie` 加 header 名稱的小寫（`modules/waf-web-acl/main.tf:18`、`loadbalancer/waf.tf:23`、`edge/waf.tf:20`）；`dev_page` rule 不要求 header（`loadbalancer/alb.tf:23-31`、`loadbalancer/envs/dev.tfvars:15`）。

**預期結果**

- `grep -c` 兩個檔都是 `0`；plan 裡 header 值顯示 `(sensitive value)`。
- 不帶 header、帶錯的 header 都回 `404`。`/dev/page` 回 api 的回應（`dev` 才有）。
- `sit` 直接連 ALB timeout。
- 兩個 WAF log 裡 `x-origin-verify` 的 `value` 都是 `REDACTED`（WAF 遮蔽後的寫法，推測），看不到原值；`RedactedFields` 有 `authorization`、`cookie`、`x-origin-verify` 三個 `SingleHeader`。
- state bucket 有 SSE 設定（`AES256` 或 `aws:kms`）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 7. CloudFront WAF 與 ALB WAF 的 rate limit

**前提**

- 階段 G、H 完成。
- 兩個 WAF 的 rate limit 預設都是每 5 分鐘、每個來源 IP 2000 次（`edge/variables.tf:28-32`、`loadbalancer/variables.tf:58-62`），allowlist 佔位 `198.51.100.0/24`（`edge/envs/dev.tfvars:12`、`loadbalancer/envs/dev.tfvars:12`）。
- design K9：只有 CloudFront WAF 看得到 client 的真實 IP；ALB WAF 在 CDN 後面看到的是 CloudFront edge 的 IP。這一版不改，這一項是量出影響有多大。

**指令**

```bash
EDGE_ACL=$(aws cloudfront get-distribution --id "$DIST_ID" --query Distribution.DistributionConfig.WebACLId --output text)
ALB_ACL=$(aws wafv2 get-web-acl-for-resource --resource-arn "$LB_ARN" --query WebACL.ARN --output text)
echo "$EDGE_ACL"; echo "$ALB_ACL"

# 規則：rate-limit 的上限與 aggregate key、managed rule、body size
for a in "$EDGE_ACL" "$ALB_ACL"; do
  r=$(cut -d: -f4 <<<"$a"); s=$([ "$r" = us-east-1 ] && echo CLOUDFRONT || echo REGIONAL)
  n=$(awk -F/ '{print $(NF-1)}' <<<"$a"); id=$(awk -F/ '{print $NF}' <<<"$a")
  aws wafv2 get-web-acl --region "$r" --scope "$s" --name "$n" --id "$id" \
    --query 'WebACL.Rules[].{name:Name,p:Priority,limit:Statement.RateBasedStatement.Limit,key:Statement.RateBasedStatement.AggregateKeyType,group:Statement.ManagedRuleGroupStatement.Name}' --output table
done

# 兩邊看到的來源 IP：edge 是 client，ALB 是 CloudFront
aws logs filter-log-events --region us-east-1 --log-group-name "aws-waf-logs-$P-$E-api-edge" --limit 50 \
  --query 'events[].message' --output text | jq -r '.httpRequest.clientIp' | sort | uniq -c | sort -rn | head
aws logs filter-log-events --log-group-name "aws-waf-logs-$P-$E-alb" --limit 50 \
  --query 'events[].message' --output text | jq -r '.httpRequest.clientIp' | sort | uniq -c | sort -rn | head
```

【寫入】打流量測 rate limit。在一台**不在** allowlist 裡的機器上，5 分鐘內送 2500 次（`dev`；只是請求，不改資源，但會讓這台機器被 edge WAF 擋幾分鐘）：

```bash
for i in $(seq 1 2500); do
  curl -s -o /dev/null -w '%{http_code}\n' "https://$API/api/quota"
done | sort | uniq -c
```

跑完之後，用上面兩段 `filter-log-events` 加 `--start-time`（測試開始的 epoch 毫秒）再看一次，記下：edge WAF 是哪一刻開始回 `BLOCK`、ALB WAF 看到幾個不同的 CloudFront IP、單一 CloudFront IP 最多幾次。

名稱怎麼來的：規則名 `rate-limit`、`aggregate_key_type = "IP"`、allowlist 用 scope-down（`modules/waf-web-acl/main.tf:112-137`）；managed rule group 與 body size 例外（`edge/waf.tf:8-12`、`loadbalancer/waf.tf:14-17`）；ALB WAF 另有 kill switch（`loadbalancer/waf.tf:2-6`）；ip set 名稱 `<web ACL 名稱>-allowlist`（`modules/waf-web-acl/main.tf:30`）。

**預期結果**

- `EDGE_ACL` 在 `us-east-1`、`global/webacl/<project>-<env>-api-edge/...`；`ALB_ACL` 在 `aws_region`、`regional/webacl/<project>-<env>-alb/...`。
- edge：`rate-limit`（30，2000，`IP`）、兩個 managed group（100、101）、`body-size-limit`（1000）。ALB：多一條 `kill-switch`（10）。
- 平常的 log：edge 的 `clientIp` 是 client 的公網 IP；ALB 的 `clientIp` 都在 CloudFront origin-facing prefix list 裡。
- 打流量時：edge WAF 在超過 2000 次後開始回 403（WAF 的 rate 計算有延遲，實際會多放一些，推測）；ALB WAF 不應該先擋。
- 結論寫進備註：一個 client 的流量在 ALB 端分散到幾個 CloudFront IP、ALB 的 `rate_limit_per_5min` 要不要調高。正式流量下，一個 CloudFront IP 代表很多 client，ALB 的 2000 次很可能太低（K9）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／ALB 端單一 IP 最多 ______ 次、建議的 ALB 上限 ______

## 8. CloudFront log 跨 region 送到 bucket

**前提**

- 階段 G 完成；有流量之後（階段 H）才會有 log。
- delivery source、destination、delivery 都在 us-east-1，bucket 在 `aws_region`（`edge/logs.tf:1-3`、`:11-16`；`modules/log-delivery/main.tf:17`、`:37`、`:69`）。
- bucket policy 允許任何 region 的 delivery source，只限本帳號（`modules/s3-bucket/main.tf:29-35`）。

**指令**

```bash
LOG_BUCKET="$P-$E-cdn-logs-$ACCOUNT"
aws logs describe-delivery-sources --region us-east-1 \
  --query "deliverySources[?name=='$P-$E-api-access'].{name:name,type:logType,arns:resourceArns,service:service}"
aws logs describe-delivery-destinations --region us-east-1 \
  --query "deliveryDestinations[?name=='$P-$E-api-bucket'].{name:name,type:deliveryDestinationType,dest:deliveryDestinationConfiguration.destinationResourceArn}"
aws logs describe-deliveries --region us-east-1 \
  --query "deliveries[?deliverySourceName=='$P-$E-api-access'].{id:id,dest:deliveryDestinationArn,type:deliveryDestinationType}"

aws s3api get-bucket-location --bucket "$LOG_BUCKET"
aws s3api get-bucket-encryption --bucket "$LOG_BUCKET" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault'
aws s3api get-bucket-policy --bucket "$LOG_BUCKET" --query Policy --output text | jq '.Statement[] | {Sid, Resource, Condition}'

# 打幾次流量，等 5–10 分鐘
for i in $(seq 1 20); do curl -s -o /dev/null "https://$API/api/quota"; done
aws s3 ls "s3://$LOG_BUCKET/AWSLogs/$ACCOUNT/" --recursive | tail -5
```

名稱怎麼來的：bucket 名稱 `"${local.name_prefix}-cdn-logs-${var.expected_account_id}"`（`edge/logs.tf:6`），沒有給 `kms_key_arn`，用 SSE-S3（`modules/s3-bucket/variables.tf:11-15`）；log-delivery 的 `name_prefix` 是 `local.cdn.name`，也就是 `<project>-<env>-api`（`edge/logs.tf:34`、`edge/distribution.tf:8`）；source、destination 名稱 `"${var.name_prefix}-${each.key}"`，key 是 `access`、`bucket`（`modules/log-delivery/main.tf:18`、`:38`；`edge/logs.tf:13-15`）；物件路徑在 `AWSLogs/<account>/` 底下（`modules/s3-bucket/main.tf:43` 的 policy resource），再往下的目錄是 AWS 的慣例（推測）。

**預期結果**

- `edge` apply 成功，沒有建 delivery 時的錯誤。失敗時把錯誤訊息貼在備註，這就是 design §11 這一點不成立的證據。
- source：`ACCESS_LOGS`，`resourceArns` 是 distribution 的 ARN。destination：`S3`，指到 `$LOG_BUCKET`。delivery 一筆。
- bucket 在 `aws_region`（`ap-northeast-1` 時 `LocationConstraint` 是 `ap-northeast-1`），SSE 是 `AES256`。
- 有流量後 5–10 分鐘內 `AWSLogs/<account>/` 底下有新物件（時間是推測，記下實際延遲）。
- 這個 bucket 跟 ALB 的 access log bucket（`<project>-<env>-alb-access-logs-<account>`，`loadbalancer/alb.tf:3`）是不同的 bucket。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／第一個 log 物件出現花了 ______

## 9. `trusted_proxies = "vpc_and_cdn"`

**前提**

- 階段 H 完成。`application/envs/dev.tfvars:14`、`sit.tfvars:14` 都是 `vpc_and_cdn`。
- `application` 在 plan 時讀 CloudFront origin-facing prefix list 的 entries，排序後跟 VPC CIDR 一起放進 api 的 `FORWARDED_ALLOW_IPS`（`application/environment.tf:6-10`、`:18-23`、`:53`）。

**指令**

```bash
TD=$(aws ecs describe-services --cluster "$P-$E-app" --services "$P-$E-api" --query 'services[0].taskDefinition' --output text)
aws ecs describe-task-definition --task-definition "$TD" \
  --query 'taskDefinition.containerDefinitions[?name==`app`]|[0].environment[?name==`FORWARDED_ALLOW_IPS`]|[0].value' --output text \
  | tr ',' '\n' > /tmp/forwarded.txt
head -1 /tmp/forwarded.txt; wc -l < /tmp/forwarded.txt

PL=$(aws ec2 describe-managed-prefix-lists --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing --query 'PrefixLists[0].PrefixListId' --output text)
aws ec2 get-managed-prefix-list-entries --prefix-list-id "$PL" --query 'Entries[].Cidr' --output text | tr '\t' '\n' | sort > /tmp/pl.txt
diff <(tail -n +2 /tmp/forwarded.txt | sort) /tmp/pl.txt && echo "CloudFront 範圍一致"

# api 記錄到的 client IP：從自己的機器打一次，再到 api 的 log 找自己的 IP
MYIP=$(curl -s https://checkip.amazonaws.com)
curl -s -o /dev/null "https://$API/api/quota"
aws logs filter-log-events --log-group-name "/ecs/$P-$E-api" --filter-pattern "\"$MYIP\"" --limit 3 --query 'events[].message' --output text

# 下一次 plan 不應該因為排序而重建 task definition
./stacks.sh "$E" application plan -- -detailed-exitcode; echo "exit=$?"
rm /tmp/forwarded.txt /tmp/pl.txt
```

名稱怎麼來的：cluster `"${local.name_prefix}-app"`、服務 `"${local.name_prefix}-api"`（`application/cluster.tf:2-3`、`application/api.tf:58`）；container 名稱 `app`（`modules/ecs-service/main.tf:13`）；log group `"/ecs/${var.name}"`（`modules/ecs-service/main.tf:5`）。`checkip.amazonaws.com` 是 AWS 的公開服務，不在 repo 裡。

**預期結果**

- 第一行是 VPC CIDR（`network/envs/<env>.tfvars:6`，佔位 `10.10.0.0/16`），其餘跟 prefix list 的 entries 完全一致。
- api 的 log 裡記到的 client 位址是 `MYIP`，不是 CloudFront 的 IP（log 格式看應用程式；uvicorn 的 access log 有 client 位址，推測）。找不到時記下 log 裡實際的位址。
- `application plan` 的 `exit=0`。AWS 改了 prefix list 的內容時會是 `exit=2`（新的 task definition），這是預期行為，記下來就好。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／api 記到的位址 ______

## 10. 回源 read timeout 60 秒與串流

**前提**

- 階段 H 完成，api 的 `/api/stream` 可以用。
- `origin_read_timeout` 預設 60（`edge/variables.tf:22-26`），不申請配額的上限；ALB 的 `idle_timeout` 是 300（`loadbalancer/variables.tf:1-5`）。串流超過 60 秒沒送任何資料，CloudFront 會先斷線（REFERENCE〈已知限制的細節〉、design §14）。
- 要知道應用程式的串流多久送一次資料（heartbeat）。這是跟應用程式的約定，repo 裡沒有。

**指令**

```bash
# 記錄每一段資料到達的時間；結束時印總時間與結束原因
( time curl -N -s -w '\nexit_http=%{http_code}\n' "https://$API/api/stream<路徑與參數>" -H "Authorization: <token>" \
  | while IFS= read -r line; do printf '%s %s\n' "$(date +%T)" "${line:0:80}"; done ) 2>&1 | tail -20
```

如果應用程式有辦法讓串流超過 60 秒不送資料（例如測試用的參數），再跑一次對照。

**預期結果**

- 有 heartbeat（間隔小於 60 秒）時，串流可以撐過 60 秒，直到應用程式自己結束或 ALB 的 300 秒。
- 超過 60 秒沒送資料時，大約在第 60 秒被切斷（CloudFront 回 504 或連線中斷，推測）。
- 記下 heartbeat 間隔與實際斷線的時間點。沒有 heartbeat 的話，開 issue 給應用程式，或評估申請提高 CloudFront 的 read timeout 配額。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／heartbeat 間隔 ______、斷線時間 ______

## 11. 換 origin verify 的值

**前提**

- 階段 H 完成，第 5 項通過。只在 `dev`，挑可以中斷的時段。
- 已知會中斷：`alb` module 的 rule 只放一個值（`modules/alb/main.tf:176-182`），design §14 已確認。這一項量中斷多久，確認 REFERENCE〈換 origin verify 的值〉的步驟可行。

**指令**

另開一個 shell，先開始探測：

```bash
while true; do printf '%s %s\n' "$(date +%T)" "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "https://$API/api/quota")"; sleep 5; done | tee rotation.log
```

主 shell，照 REFERENCE〈換 origin verify 的值〉第 2–4 步：

```bash
# 【寫入】
export TF_VAR_origin_verify_header_value=<新值，至少 16 字元>
date +%T; ./stacks.sh dev loadbalancer apply --yes; date +%T
date +%T; ./stacks.sh dev edge apply --yes;         date +%T
```

結束後停掉探測，算 404 的時間：

```bash
awk '$2=="404"{if(!s)s=$1; e=$1} END{print "404 從", s, "到", e}' rotation.log
```

**預期結果**

- `loadbalancer` apply 結束前後開始回 404；`edge` apply 結束時（distribution 部署完）404 停止，之後回正常的狀態碼。
- 中斷長度約等於 `edge` apply 的時間，REFERENCE 估計幾分鐘到十幾分鐘。記下實際分鐘數。
- 中斷之後第 5、6 項的 `curl` 檢查再跑一次都通過。
- 中斷超過可接受的範圍時，開 issue 給 platform team：讓 `alb` module 的 rule 接受多個值（design §4.1 的做法）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／中斷 ______ 分鐘

## 12. secret 用 `moved` 搬進 module

**前提**

- 這一項只對「v9 之前就用 example2 apply 過 `foundation`」的專案有意義：舊的 address 是 `aws_secretsmanager_secret.this["<key>"]`，v9 改成 `module.secrets["<key>"].aws_secretsmanager_secret.this`，每個 key 一個 `moved`（`foundation/secrets.tf:27-35`）。
- 第一次就用 v9 版本 apply 的專案沒有舊 address，`moved` 不會做事，這一項記「不適用」。
- 舊版的寫法：名稱、描述、`recovery_window_in_days = 7`、`Name` tag 跟現在一樣，沒有 KMS key（platform repo 的 `git show 4e2a6ad^:templates/example2/infra/terraform/foundation/secrets.tf`）。所以搬完應該沒有任何屬性變更。

**指令**

在 apply v9 的 `foundation` **之前**：

```bash
for k in app-signing-public-key app-signing-private-key; do
  aws secretsmanager describe-secret --secret-id "$P-$E/$k" --query '{arn:ARN,kms:KmsKeyId,tags:Tags,created:CreatedDate}'
  aws secretsmanager list-secret-version-ids --secret-id "$P-$E/$k" --query 'Versions[].[VersionId,VersionStages[0]]' --output text
done

./stacks.sh "$E" foundation plan -- -no-color | tee foundation-plan.txt
grep -E 'has moved to|will be created|will be destroyed|must be replaced|will be updated|^Plan:' foundation-plan.txt
```

plan 看起來對了，【寫入】`./stacks.sh dev foundation apply`，再跑一次上面的 `describe-secret` 與 `list-secret-version-ids` 比對，最後：

```bash
./stacks.sh "$E" foundation plan -- -detailed-exitcode; echo "exit=$?"
```

名稱怎麼來的：secret 名稱 `"${local.name_prefix}/app-signing-public-key"`、`.../app-signing-private-key`（`foundation/secrets.tf:3-4`）；module 的 resource 名稱 `aws_secretsmanager_secret.this`，加 `Name = var.name` tag（`modules/secrets-manager-secret/main.tf:3-10`）；`kms_key_arn = null`、7 天（`foundation/secrets.tf:9-10`）。

**預期結果**

- plan 有兩行 `has moved to`，`Plan: 0 to add, 0 to change, 0 to destroy`（或只有 SSM 的值不變的訊息）。出現 `will be destroyed` 或 `must be replaced` 就**不要** apply，把 plan 貼在備註。
- apply 前後 ARN、`KmsKeyId`（沒有值，用 `aws/secretsmanager`）、tag、版本 ID 與 `AWSCURRENT` 都一樣。
- apply 後再 plan，`exit=0`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ 不適用 □ ／備註 ______

## 13. destroy 的阻擋點

**前提**

- 只在 `dev`，所有驗證做完之後。這會刪掉整個環境。
- 先讀 REFERENCE〈destroy 之前〉。這一項只看 v9 加的資源：distribution、CloudFront WAF、CloudFront log bucket、兩張憑證、hosted zone、secret。
- `stacks.sh` 的 destroy 反向跑：`postdeploy operation application agent edge loadbalancer bridge iam database network certificate dns foundation containerimage`（`stacks.sh:8`、`:93-97`）。

**指令**

```bash
./stacks.sh dev all destroy --dry-run          # 確認順序

# destroy 前：zone 裡有沒有 Terraform 以外的 record（NS、SOA 之外，又不是驗證 CNAME 與 api、origin-api 的）
aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" --query 'ResourceRecordSets[].[Name,Type]' --output text

# 【寫入】清空 CloudFront log bucket（沒開 versioning：vended_logs 不能配 versioning）
aws s3 rm "s3://$P-$E-cdn-logs-$ACCOUNT" --recursive
```

然後一個 stack 一個 stack 往回 destroy（【寫入】`./stacks.sh dev <stack> destroy`），在下面幾個點停下來看：

```bash
# edge destroy 之後：distribution 與 edge WAF 不見了，CloudFront 憑證不再被使用
aws cloudfront get-distribution --id "$DIST_ID" 2>&1 | tail -1
aws wafv2 list-web-acls --region us-east-1 --scope CLOUDFRONT --query "WebACLs[?Name=='$P-$E-api-edge']"
aws acm describe-certificate --region us-east-1 --certificate-arn "$CF_CERT" --query 'Certificate.InUseBy'

# loadbalancer destroy 之後：ALB 憑證不再被使用
aws acm describe-certificate --certificate-arn "$ALB_CERT" --query 'Certificate.InUseBy'

# certificate destroy 之後：zone 只剩 NS 與 SOA
aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" --query 'ResourceRecordSets[].[Name,Type]' --output text

# foundation destroy 之後：secret 進入待刪除，7 天內不能同名重建
aws secretsmanager describe-secret --secret-id "$P-$E/app-signing-public-key" --query DeletedDate
```

`dns` destroy 之後，到上層網域刪掉 `<zone>` 的 NS 委派（人工）。

名稱怎麼來的：log bucket 的 `force_destroy` 預設 `false`（`modules/s3-bucket/variables.tf:171-174`），versioning 與 `vended_logs` 互斥（`modules/s3-bucket/variables.tf:96-99`）；zone 的 `force_destroy` 預設 `false`（`modules/route53-zone/variables.tf:34-38`）；憑證 `create_before_destroy`（`modules/acm-certificate/main.tf:22-24`）；secret 的 7 天（`foundation/secrets.tf:10`）。

**預期結果**

- 沒清空 log bucket 就 destroy `edge` 會失敗（`BucketNotEmpty`）；清空之後成功。`edge` destroy 要等 distribution 停用，十幾分鐘（REFERENCE〈destroy 之前〉）。記下實際時間。
- `edge` destroy 後：`get-distribution` 回 `NoSuchDistribution`；edge WAF 查不到；CloudFront 憑證 `InUseBy` 是空的。
- `loadbalancer` destroy 後：ALB 憑證 `InUseBy` 是空的；`certificate` destroy 成功。兩張憑證共用的 `api` 驗證 record 只會被刪一次，第二個刪除不應該報錯（provider 對已經不存在的 record 的處理，推測）；報錯就貼在備註。
- `certificate` destroy 後 zone 只剩 NS 與 SOA，`dns` destroy 成功；有 Terraform 以外的 record 時會失敗（`HostedZoneNotEmpty`）。
- `foundation` destroy 後 secret 有 `DeletedDate`。
- 不照反向順序、單獨 destroy `certificate` 時，憑證還被 ALB 或 CloudFront 用，會失敗（`ResourceInUseException`）。這一點不用故意測，遇到就記下。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／`edge` destroy 花了 ______、卡住的資源 ______

---

## 結果怎麼回寫

執行人是負責 apply 的專案 app team 成員；回寫分三處，都用 PR：

| 回寫到哪裡 | 誰改 | 怎麼改 | 誰審 |
|---|---|---|---|
| 本 runbook 的「結果紀錄」 | 執行人 | 每一項填完那一行；不通過的附 issue 連結 | 跟下一列同一個 PR |
| `templates/example2/infra/REFERENCE.md`〈已知限制的細節〉的「CloudFront 與 ALB」與 README〈已知限制〉的「DNS 與憑證」「CloudFront」兩條 | 執行人 | 已確認的條目改成實際結果，例如 `通過（YYYY-MM-DD，dev）` 或 `不通過：<一句話>（#issue）`；第 4 項的 `MaxEntries` 與配額、第 7 項建議的 ALB 上限、第 11 項的中斷分鐘數直接寫進去。prefix list ID 查證過就把 `network/envs/*.tfvars` 的註解一起改掉 | platform team ＋ 專案代表（`/templates/` 的 CODEOWNERS） |
| `docs/design/v9/design-docs.md` §11 | platform team | 跟 example2 有關的點後面加 `→ 已確認（YYYY-MM-DD，runbook 第 <n> 項）`，或 `→ 不成立：<實際行為>，改法見 #issue` | platform team |

不通過的處理：

- 問題在 module（例如 `alb`、`cloudfront-distribution`、`acm-certificate`、`log-delivery`）：照 `docs/guides/team-roles.md`〈交接點〉在本 repo 開 issue 給 platform team，附指令輸出。
- 問題在範本的 stack 或 tfvars：開 issue 並標 `templates/example2`，修正走一般的範本改版 PR。
- 同一項修好後重跑，結果紀錄寫新的一行，舊的不刪。
