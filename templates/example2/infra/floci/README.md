# 用 Floci 在本機跑 example2

[Floci](https://floci.io) 是在本機模擬 AWS API 的工具。`floci.sh` 把 example2 的 14 個 stack 照 `stacks.sh` 的順序 apply 到 Floci，再檢查結果，最後 destroy。整個過程不連任何 AWS 帳號，也不改範本本身。

跟 example6、account-baseline 不一樣的是，example2 在 Floci 裡會真的跑起來：ECS 的 `api`、`worker` 是真的 container，Aurora 是真的 Postgres，兩組 Redis 是真的 Valkey，ALB 會把請求轉給 `api`。所以除了確認 stack 串得起來，也可以從本機送一個請求進去，看它經過哪些服務。

這不等於雲端驗證。IAM 權限夠不夠、CloudFront 與 WAF 的實際行為、配額與費用，還是要照 [`docs/guides/cloud-verification-example2.md`](../../../../docs/guides/cloud-verification-example2.md) 在真實帳號確認。

## 怎麼跑

需要 Terraform、AWS CLI、`openssl`、`rsync`、Python 3，以及 Docker 或 Podman 其中一個。Module 從 HCP private registry 下載，所以也要有 HCP token（見 [`docs/guides/consuming-modules.md`](../../../../docs/guides/consuming-modules.md)）。

```bash
./floci.sh run      # up → prepare → init → apply → verify → destroy，約 17 分鐘
./floci.sh down     # 移除 Floci 和它啟動的 container、volume
```

想留著環境慢慢看，就分段跑，最後再 `destroy`、`down`：

```bash
./floci.sh up && ./floci.sh prepare && ./floci.sh init && ./floci.sh apply
./floci.sh status   # 起了哪些服務
./floci.sh trace    # 請求怎麼走
./floci.sh destroy && ./floci.sh down
```

Floci 的資料只放在記憶體，container 重啟就會清空；這時要先 `down`，再從 `up` 重跑。Floci 固定用 port 4566，同一時間只能跑一個範本的 Floci。

### Podman 要先設定兩件事

在 macOS 上用 Podman 時，`floci.sh up` 會先檢查 Podman VM 裡的這兩個設定，沒設好就印出要執行的指令：

1. 允許用 HTTP 連 `localhost:4566`，Floci 才能從自己的 ECR 拉測試用映像。
2. 封鎖假帳號 `111111111111` 在真實 AWS 的 ECR（`111111111111.dkr.ecr.ap-northeast-1.amazonaws.com`）。ECS、Lambda、AgentCore 的 module 只接受 AWS 格式的映像網址，Floci 拉映像時會轉回自己的 registry；萬一沒轉，Podman 會直接拒絕，不會連到 AWS。

設定完要重啟 VM 裡的 Podman API 服務：`podman machine ssh systemctl --user restart podman.service`。

## 看起了哪些服務：`status`

`./floci.sh status` 印出四段：

| 段落 | 內容 |
|---|---|
| 各 stack 的 AWS 資源 | 每個 stack 在 Floci 建了哪些資源，依類型計數 |
| Floci 起的 container | ECS task、RDS、Redis、ECR registry 等真的在跑的 container，以及映像與狀態 |
| ECS | 每個 service 的期望數與執行數 |
| ALB target health、RDS 與 Redis endpoint | ALB 後面的 target 是否 healthy；資料庫、RDS Proxy、Redis 的 endpoint |

實際跑起來的 container 長這樣（名稱裡的 ID 每次不同）：

```text
floci-aws-ecr-registry                          docker.io/library/registry:2
floci-aws-rds-cluster-...                       docker.io/library/postgres:16.6-alpine
floci-aws-valkey-example-dev-rate-limit-0001-00x docker.io/valkey/valkey:8
floci-aws-valkey-example-dev-stream-0001-00x     docker.io/valkey/valkey:8
floci-aws-ecs-...-app                           localhost:4566/111111111111/ap-northeast-1/example-api:0.1.0
floci-aws-ecs-...-app                           localhost:4566/111111111111/ap-northeast-1/example-worker:0.1.0
```

ECS task 的映像來自 `localhost:4566`，也就是 Floci 自己的 ECR，不是 AWS。

## 看請求怎麼走：`trace`

正式環境的路徑是 client → CloudFront（加上 origin verify header）→ ALB → ECS `api` → 資料庫、Redis、AgentCore。Floci 不會真的經過 CloudFront，所以 `trace` 從 ALB 開始，自己帶上 origin verify header，模擬 CloudFront 送來的請求：

```text
本機 curl ──https://localhost:8443（Host: api.dev.example.com，X-Origin-Verify）──▶ ALB（Floci）
   ALB 照 listener rule 轉給 target group ──▶ ECS api task（真的 container）
      api ──▶ RDS Proxy ──▶ Aurora（Postgres container）
      api ──▶ rate-limit Redis（Valkey container，經 Floci 的 cache proxy）
      api ──▶ stream Redis ──▶ worker 從 stream 讀
      api ──▶ AgentCore Runtime（Floci 的 stub）
```

`api` 用的是 `app-stub/` 的測試映像，不是應用程式。它收到請求後，依序連每個依賴，把每一跳的結果回傳，所以一個請求就看得到整條路徑。`trace` 先確認 ALB 的規則：沒帶 origin verify header、或打不在規則裡的 path，都要回 404。再印出每一跳：

| 標記 | 意思 |
|---|---|
| `OK` | 這一跳通了，後面是對方的回應（例如 Postgres 版本、AgentCore 的回應） |
| `KN` | Floci 的已知限制，見下面〈Floci 驗不到的部分〉 |
| `NG` | 失敗，`verify` 會判不通過 |

最後印出 `worker` container 的最近幾行 log，看它有沒有從 stream Redis 讀到 `api` 寫進去的訊息。

## `floci.sh` 做了什麼

1. 把 `../terraform` 複製到 `$TMPDIR/floci-example2`（可以用 `FLOCI_WORK_DIR` 改位置），之後只動複本。複本放在 repo 外面，因為 `scripts/validate.sh` 會掃 `templates/` 底下所有的 `.tf`。
2. 每個 stack 加一個 `floci_override.tf`（內容見 `provider_override.tf.tmpl`），寫死假的 access key。就算 `AWS_ENDPOINT_URL` 漏設，請求也會因為驗證失敗被擋下，碰不到真實帳號。access key 用 12 位數的 `111111111111`，Floci 會把它當成帳號 ID 回傳，`allowed_account_ids` 的檢查才過得了。
3. 每個 stack 的 `envs/dev.tfbackend` 換成 Floci 裡的 S3，state key 沿用原本的值。所有 stack 共用一份 provider cache（`$TMPDIR/floci-terraform-plugin-cache`），不會每個 stack 各下載一份。
4. origin verify 的值用 `openssl` 產生，只存在複本目錄，`loadbalancer` 從 `TF_VAR_origin_verify_header_value` 讀，`trace` 拿來送請求。
5. 用 `app-stub/` 建 `api` 與 `worker` 的映像，用 `lambda-stub/` 建兩個 import Lambda 的映像，推到 Floci 的 ECR。`agent` 不建映像，因為 Floci 的 AgentCore 不會啟動 container。

## Floci 驗不到的部分

### 複本裡改過的地方

| 位置 | 改了什麼 | 原因 |
|---|---|---|
| `containerimage/ssm-outputs.tf` | 發布的 ECR 網址把 host 換成 `amazonaws.com` 格式 | Floci 的 ECR 回傳 `.localhost:4566` 格式，ECS、Lambda、AgentCore 的 module 不接受。Floci 拉映像時會轉回自己的 registry |
| `network/envs/dev.tfvars`、`application/environment.tf` | CloudFront 的 prefix list 換成 Floci 裡另建的 `floci-cloudfront-origin-facing` | Floci 沒有 AWS 內建的 prefix list，自建的名稱又不能用 `com.amazonaws.` 開頭 |
| `edge/logs.tf`、`agent/logs.tf`、`loadbalancer/alb.tf` 的 `alb_access_logs` | 拿掉 | Floci 2.4.0 不支援 CloudWatch Logs delivery |
| `postdeploy` 的 `tracing_enabled` | 改成 `false` | trace 送 X-Ray 也走 log delivery |
| `operation` 的 `bastion_enabled` | 改成 `false` | Floci 查不到 `t4g.nano` 這個 instance type；bastion 不在請求路徑上 |
| `agent` 下載的 `agentcore-runtime` module | 拿掉 `lifecycle_configuration` | Floci 不保存這個設定，provider 會報 inconsistent result。session 逾時的設定要在真實帳號驗證 |

### 第二次 plan 的已知差異

都直接呼叫 Floci 的 API 確認過，是 Floci 回傳的值跟 AWS 不一樣：

| 資源 | Floci 的行為 |
|---|---|
| `database`：Aurora cluster | 不回備份保留天數、備份與維護時段、log 匯出、security group；port 回 proxy 的 7001 |
| `database`：cluster parameter group | 不保存參數 |
| `database`：兩組 Redis 與它們的 SSM endpoint | 不保存 log delivery 設定。兩組都要 6379，晚建的那組被分到別的 port，plan 每次都要重建它 |
| `edge`：CloudFront distribution | 不保存 `WebACLId` |
| `operation`：兩個 import Lambda | 沒設定時仍回空的 `ImageConfig` |
| `postdeploy`：`api` 的 p95 延遲告警 | 不回 `ExtendedStatistic` |

### `trace` 的已知限制（`KN`）

- **Redis 要求登入**：兩組 Redis 開了傳輸加密、沒設 AUTH token，在 AWS 上用 TLS 就能連。Floci 的 cache proxy 接受 TLS，但還是要求 AUTH，所以這兩跳停在「Authentication required」。走到這一步，代表 endpoint、port 和 TLS 都接對了。連線被拒、逾時等其他錯誤仍然判失敗。因為這樣，`worker` 也讀不到 stream。
- **Redis 的 port 可能指到另一組**：上一節的 port 問題也讓 SSM 裡的 endpoint 可能寫成另一組 Redis 的 port。
- **AgentCore 是 stub**：Floci 不會真的跑 agent，呼叫一律回固定的 `{"output":"yes"}`。這一跳只證明 `api` 拿到的 runtime ARN 是對的。

### 本來就驗不到的

- CloudFront 不會真的轉送請求，`trace` 從 ALB 開始。CloudFront、WAF 規則和 DNS 查詢都沒有測。
- ACM 憑證一建立就是簽發狀態，ALB 的 HTTPS 用的是 Floci 自己產生的憑證（所以 `trace` 用 `curl -k`）。
- Floci 預設不檢查 IAM policy，也不依 security group 擋流量，所以權限和網路隔離都看不出來。
- 告警、dashboard、log metric filter 建得起來，但 Floci 不會產生真的指標，告警不會觸發。

## 版本

Floci 固定在 `2.4.0`（2026-10-31），要換版本就設定 `FLOCI_IMAGE`。換版後，上面的已知差異和改過的地方都要重新確認。
