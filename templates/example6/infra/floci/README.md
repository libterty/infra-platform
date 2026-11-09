# 用 Floci 在本機跑 example6

[Floci](https://floci.io) 是在本機模擬 AWS API 的工具。`floci.sh` 會把 example6 照 `stacks.sh` 的順序 apply 到 Floci，再檢查結果，最後 destroy。整個過程不連任何 AWS 帳號，也不改範本本身。

這不等於雲端驗證。Floci 只能證明 stack 之間串得起來；IAM 權限夠不夠、配額、網路和 CloudFront 的實際行為，還是要照 [`docs/guides/cloud-verification-example6.md`](../../../../docs/guides/cloud-verification-example6.md) 在真實帳號確認。

## 怎麼跑

需要 Terraform、AWS CLI、`openssl`、`rsync`，以及 Docker 或 Podman 其中一個。Module 從 HCP private registry 下載，所以也要有 HCP token（見 [`docs/guides/consuming-modules.md`](../../../../docs/guides/consuming-modules.md)）。

```bash
./floci.sh run      # up → prepare → init → apply → verify → destroy
./floci.sh down     # 移除 Floci 和它啟動的 container、volume
```

要停在中間看結果，就分段跑：`up`、`prepare`、`init`、`apply`、`verify`、`destroy`。Floci 的資料只放在記憶體，container 重啟就會清空；這時要先 `down`，再從 `up` 重跑。

在 macOS 上用 Podman 時，要先讓 Podman 可以用 HTTP 連 `localhost:4566`（Floci 的 ECR），不然 Lambda 拉不到映像。`floci.sh up` 檢查到沒設定時，會印出要執行的指令。設定完如果 Floci 已經在跑，要重啟 VM 裡的 Podman API 服務（`podman machine ssh systemctl --user restart podman.service`），新設定才會生效。

## `floci.sh` 做了什麼

1. 把 `../terraform` 複製到 `$TMPDIR/floci-example6`（可以用 `FLOCI_WORK_DIR` 改位置），之後只動複本。複本放在 repo 外面，因為 `scripts/validate.sh` 會掃 `templates/` 底下所有的 `.tf`。
2. 每個 stack 加一個 `floci_override.tf`（內容見 `provider_override.tf.tmpl`），寫死假的 access key。就算 `AWS_ENDPOINT_URL` 漏設，請求也會因為驗證失敗被擋下，碰不到真實帳號。access key 用 12 位數的 `111111111111`，Floci 會把它當成帳號 ID 回傳，`allowed_account_ids` 的檢查才過得了。
3. 每個 stack 的 `envs/dev.tfbackend` 換成 Floci 裡的 S3，state key 沿用原本的值。
4. 照 REFERENCE.md 第 3 步產生 origin verify 的值，寫進 secret，再讀回來設成 `TF_VAR_origin_verify_header_value`。
5. 用 `lambda-stub/` 建 API 映像。這是測試用的 Lambda，不是應用程式：它照 API 的約定檢查 origin verify header，通過後寫一筆資料到 DynamoDB 再讀回來。

## verify 檢查什麼

| 項目 | 怎麼判斷 |
|---|---|
| apply 後再 plan 一次 | 每個 stack 都要沒有變更；只允許下面列出的 Floci 差異 |
| 跨 stack 契約 | 列出 `/example/dev` 底下的 SSM 參數 |
| 沒帶 origin verify header | `GET /api/health` 回 403 |
| 帶 origin verify header | `GET /api/health` 回 200，而且 DynamoDB 寫入後讀得回來 |
| 沒帶 JWT | `GET /api/items` 回 401（authorizer 擋下，沒有進到 Lambda） |

API 的請求一律送到 `localhost:4566`，用 `Host` header 指定 API；就算 Terraform 回報的網址是 `amazonaws.com`，也不會連出去。

## Floci 驗不到的部分

### 從複本拿掉的檔案

| 檔案 | 原因 |
|---|---|
| `web/logs.tf` | Floci 2.4.0 不支援 CloudWatch Logs delivery，`PutDeliveryDestination` 回 `UnsupportedOperation`。CloudFront 標準 log 要在真實帳號驗證 |

### 第二次 plan 的已知差異

三筆都直接呼叫 Floci 的 API 確認過，是 Floci 回傳的值跟 AWS 不一樣：

| 資源 | Floci 的行為 |
|---|---|
| `api`：`module.function.aws_lambda_function.this` | 沒設定 `image_config` 時，`GetFunction` 仍回傳空的 `ImageConfig`。AWS 會省略這個欄位 |
| `web`：`module.cdn.aws_cloudfront_distribution.this` | 不保存 `WebACLId`，讀回來是 null |
| `web`：`module.cdn.aws_cloudfront_function.spa_fallback[0]` | 不保存 CloudFront function 的 tag |

### 複本裡改過的寫法

`api/function.tf` 的 `image_uri` 是用 repository URL 組出來的。Floci 的 ECR 回傳 `<帳號>.dkr.ecr.<region>.localhost:4566/...`，`lambda-function` module 只接受 `amazonaws.com` 的網址，所以複本把 host 換回 AWS 的格式，Floci 拉映像時會再轉回自己的 registry。

不要為了省事，把映像直接用 `amazonaws.com` 的名稱 tag 在本機。Floci 2.4.0 遇到這種映像還是會去拉，結果會連到真的 ECR。`floci.sh` 發現有這種映像時會直接停止。

### 本來就驗不到的

- Floci 預設不檢查 IAM policy，所以 `iam` stack 給的權限夠不夠，這裡看不出來。
- CloudFront、WAF、Route 53 這次只確認資源建得起來，沒有測 CloudFront 的回應、WAF 規則和 DNS 查詢。
- ACM 憑證一建立就是 `ISSUED`，看不出 DNS 驗證的設定對不對。
- 配額、費用、各 region 能不能用，都要在真實帳號確認。

## 版本

Floci 固定在 `2.4.0`（2026-10-31），要換版本就設定 `FLOCI_IMAGE`。換版後，上面的已知差異和拿掉的檔案都要重新確認。
