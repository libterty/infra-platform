# 用 Floci 在本機跑 example4

[Floci](https://floci.io) 是在本機模擬 AWS API 的工具。`floci.sh` 把 example4 的 stack 照 `stacks.sh` 的順序 apply 到 Floci，再檢查結果，最後 destroy。整個過程不連任何 AWS 帳號，也不改範本本身。

12 個 stack 跑 11 個：`bi` 用的 QuickSight 在 Floci 沒有對應的 API，所以略過，也沒有其他 stack 讀它的輸出。`vpn` 照常跑，dev 預設兩種 VPN 都關，只發布 SSM 參數。

資料平台的幾個元件在 Floci 裡會真的跑起來：OpenSearch 是真的 OpenSearch 2.19.5 container，Redshift Serverless 背後是 Postgres container，Athena 用 DuckDB container 執行 SQL，Kinesis 收到的資料會由 Firehose 拉出來寫進 S3。所以除了確認 stack 串得起來，還能從 Kinesis 送資料進去，看它流到哪裡。

這不等於雲端驗證。IAM 權限夠不夠、VPC 內的連線、OpenSearch 的 FGAC 與 UltraWarm、cold storage、Glue job 的實際執行、配額與費用，還是要照 [`docs/guides/cloud-verification-example4.md`](../../../../docs/guides/cloud-verification-example4.md) 在真實帳號確認。

## 怎麼跑

需要 Terraform、AWS CLI、`curl`、`gzip`、`rsync`、Python 3，以及 Docker 或 Podman 其中一個。Module 從 HCP private registry 下載，所以也要有 HCP token（見 [`docs/guides/consuming-modules.md`](../../../../docs/guides/consuming-modules.md)）。

```bash
./floci.sh run      # up → prepare → init → apply → verify → destroy，約 30 分鐘
./floci.sh down     # 移除 Floci 和它啟動的 container、volume
```

想留著環境慢慢看，就分段跑，最後再 `destroy`、`down`：

```bash
./floci.sh up && ./floci.sh prepare && ./floci.sh init && ./floci.sh apply
./floci.sh status   # 起了哪些服務
./floci.sh trace    # 資料怎麼流
./floci.sh destroy && ./floci.sh down
```

時間大多花在 OpenSearch：aws provider 建立 domain 後固定先等 10 分鐘才開始查狀態，destroy 也一樣，跟 Floci 多快建好無關。

Floci 的資料只放在記憶體，container 重啟就會清空；這時要先 `down`，再從 `up` 重跑。Floci 固定用 port 4566，同一時間只能跑一個範本的 Floci。

這個範本沒有 ECR 映像，不需要 example2 那樣的 Podman registry 設定。Floci 第一次會從 Docker Hub 拉 OpenSearch、Postgres、DuckDB 的映像。

## 看起了哪些服務：`status`

`./floci.sh status` 會印出三段：

| 段落 | 內容 |
|---|---|
| 各 stack 的 AWS 資源 | 每個 stack 在 Floci 建了哪些資源，依類型計數 |
| Floci 起的 container | OpenSearch、Redshift 用的 Postgres、Athena 用的 DuckDB，以及映像與狀態 |
| 資料管線 | Kinesis stream、兩個 Firehose 與它們的 S3 目的地、OpenSearch 的 endpoint 與本機連得到的位址、Glue workflow 與 job、Athena workgroup、Redshift workgroup 的 endpoint、DynamoDB table |

實際跑起來的 container 長這樣：

```text
floci-aws-opensearch-111111111111-ap-northeast-1-example-dev-search           docker.io/opensearchproject/opensearch:2.19.5
floci-aws-redshift-111111111111-serverless_ap-northeast-1_example-dev-warehouse docker.io/library/postgres:15-alpine
floci-aws-duck                                                                 docker.io/floci/floci-duck:latest
```

## 看資料怎麼流：`trace`

正式環境的路徑是：資料進 Kinesis，兩個 Firehose 各自讀出來，一個寫進 S3 raw，一個寫進 OpenSearch；raw 有新物件時，S3 的事件經 EventBridge 啟動 Glue workflow，Glue job 把 raw 轉成 curated；Athena 和 Redshift 負責查詢，DynamoDB 記錄匯入狀態。`trace` 照這個順序走一次：

```text
trace ──PutRecords 5 筆──▶ Kinesis example-dev-events
   Firehose example-dev-to-raw    ──▶ S3 raw（gzip JSON，raw/yyyy/MM/dd/HH/）
   Firehose example-dev-to-search ──▶ OpenSearch（Floci 不支援，見 KN）
   trace 直接寫入同樣 5 筆        ──▶ OpenSearch example-dev-events（index template、ISM）
   S3 raw 新物件 ──▶ EventBridge rule ──▶ Glue workflow（Floci 不支援，見 KN）
   trace 手動啟動 ──▶ Glue job
   Athena workgroup ──▶ Glue catalog ──▶ S3 raw 裡剛寫入的 5 筆
   Redshift Data API ──▶ Redshift Serverless（Postgres container）
   DynamoDB example-dev-ingest-state：寫一筆再讀回來
```

每次 trace 的資料都帶一個 `run` 編號，後面各跳只算這次寫進去的筆數。每一跳標一個記號：

| 標記 | 意思 |
|---|---|
| `OK` | 這一跳通了，後面是確認到的結果（例如筆數、mapping、ISM policy、資料庫版本） |
| `KN` | Floci 的已知限制，見下面〈Floci 驗不到的部分〉 |
| `NG` | 失敗，`verify` 會判不通過 |

有兩跳是 trace 代替做的：

- OpenSearch：Floci 的 Firehose 不會寫進 OpenSearch，所以 trace 用 bulk API 直接寫入同樣的 5 筆，確認 `search-config` 設定的 index template（`@timestamp` 是 `date`）和 ISM policy 有套到新的 index。
- Athena：Floci 的 crawler 不會讀 S3 建 table，所以 trace 在 raw database 建一張 `floci_trace` table 代替，再透過 workgroup 查剛寫進 raw 的資料。destroy 前會刪掉這張 table。

Firehose 平常照範本的 buffering interval 寫出（`to-raw` 是 900 秒）。`floci.sh up` 啟動 Floci 時設定每累積 5 筆就寫出，所以 trace 送完幾秒內就看得到 S3 的物件。

## `floci.sh` 做了什麼

1. 把 `../terraform` 複製到 `$TMPDIR/floci-example4`（可以用 `FLOCI_WORK_DIR` 改位置），之後只動複本。複本放在 repo 外面，因為 `scripts/validate.sh` 會掃 `templates/` 底下所有的 `.tf`。
2. 每個 stack 加一個 `floci_override.tf`（內容見 `provider_override.tf.tmpl`），寫死假的 access key。就算 `AWS_ENDPOINT_URL` 漏設，請求也會因為驗證失敗被擋下，碰不到真實帳號。access key 用 12 位數的 `111111111111`，Floci 會把它當成帳號 ID 回傳，`allowed_account_ids` 的檢查才過得了。
3. 每個 stack 的 `envs/dev.tfbackend` 換成 Floci 裡的 S3，state key 沿用原本的值。所有 stack 共用一份 provider cache（`$TMPDIR/floci-terraform-plugin-cache`），不會每個 stack 各下載一份。
4. `foundation` apply 之後寫入 OpenSearch master secret 的值，做法跟 REFERENCE.md〈前置作業〉第 2 項一樣：用 `get-random-password` 產生，經管線寫入，密碼不出現在指令參數和 shell 變數裡。
5. 一次 apply 一個 stack。`search-config` 要連 OpenSearch container 對外的 port，這個 port 要等 `search` 建好 domain 才有。
6. destroy 照 REFERENCE.md〈destroy〉的步驟做：先清空 bucket（含舊版本與刪除標記），在複本的 `storage` 加上 `deletion_protection = false` 再 apply 一次，把 `warehouse` 的 `prevent_destroy` 改成 `false`，再依反向順序 destroy。Floci 不支援 `DeleteResourcePolicy`，所以 `search` 的 CloudWatch Logs resource policy 改成從 state 移除，`down` 時跟著 Floci 一起清掉。

## Floci 驗不到的部分

### 複本裡改過的地方

| 位置 | 改了什麼 | 原因 |
|---|---|---|
| `stacks.sh` 的 `ORDER` | 拿掉 `bi` | Floci 沒有 QuickSight |
| `search` 下載的 `opensearch-domain` module | 拿掉 `vpc_options` | Floci 對 VPC 裡的 domain 回 `Endpoint`，不回 `Endpoints["vpc"]`，provider 讀回時報錯。拿掉後 domain 當成公開的，VPC 放置要在真實帳號驗證 |
| `search-config` 的 tfvars | `warm_days`、`cold_days` 改成 `null`，ISM 只剩 hot → delete | Floci 的 OpenSearch 是開源版，沒有 AWS 的 UltraWarm 與 cold storage，ISM 不認得 `warm_migration`、`cold_migration`、`cold_delete` |
| `search-config` 的 `writer_roles` | 改成空的，`firehose_writer_role` 直接發布範本原本的名稱 `firehose_writer` | Floci 的 OpenSearch 關掉了 security plugin，FGAC 的 role 與 role mapping 建不起來 |
| `search-config` 的 opensearch provider | `url` 改成 OpenSearch container 在本機的位址（`floci_vars.tf`） | Floci 發布的 endpoint 是 container 內部的 `http://` 位址，本機連不到，而且範本會在前面再加 `https://` |
| `analytics` 的 `named_queries` | 改成空的 | Floci 2.4.0 不支援 `CreateNamedQuery` |

### 第二次 plan 的已知差異

| 資源 | 原因 |
|---|---|
| `search`：OpenSearch domain | Floci 不回 dedicated master、UltraWarm、cold storage、zone awareness 與 log publishing 設定 |
| `analytics`：Athena workgroup | Floci 不回查詢結果的 SSE-KMS 加密設定 |
| `pipeline`：Firehose `to-search` 與它的 SSM 參數 | Floci 不保存 OpenSearch 目的地，讀回來是 `extended_s3`，plan 每次都要重建 |

### `trace` 的已知限制（`KN`）

- **Firehose 不送 OpenSearch**：Floci 的 Firehose 只送 S3。沒有 S3 目的地的 `to-search` 會把資料寫進 Floci 自己的 `floci-firehose-results` bucket。Firehose 從 VPC 內寫入 OpenSearch、SigV4 與 FGAC 的權限，都要在雲端驗證。
- **EventBridge 不啟動 Glue workflow**：S3 的事件會送到 EventBridge，rule 也比對得到，但 Floci 不支援 Glue workflow 當 target，所以 workflow 不會跑。
- **Glue job 是模擬的**：job run 會變成 `SUCCEEDED`，但 Floci 不執行 script，curated 不會有資料。

### 本來就驗不到的

- Floci 預設不檢查 IAM policy，也不依 security group 擋流量，所以權限和網路隔離都看不出來。
- Athena 的查詢結果寫到 Floci 自己的 `floci-athena-results`，不是 workgroup 設定的 bucket，所以結果的位置與 KMS 加密沒有測。
- Redshift Serverless 背後是 Postgres，`select version()` 回的是 Postgres 的版本；Redshift 特有的 SQL、RPU 用量上限都沒有測。
- 告警建得起來，但 Floci 不會產生真的指標，告警不會觸發。
- Glue Data Catalog 加密只確認 API 收下設定，加密行為沒有測。

## 版本

Floci 固定在 `2.4.0`（2026-10-31），要換版本就設定 `FLOCI_IMAGE`。換版後，上面的已知差異和改過的地方都要重新確認。
