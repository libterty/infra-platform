# 用 Floci 在本機跑 account-baseline

[Floci](https://floci.io) 是在本機模擬 AWS API 的工具。`floci.sh` 會把 account-baseline 照 `stacks.sh` 的順序 apply 到 Floci，再檢查結果，最後 destroy。整個過程不連任何 AWS 帳號，也不改範本本身。

這不等於雲端驗證。Floci 只能證明 stack 之間串得起來、帳號層的設定建得起來。log 和 finding 有沒有真的送出、IAM 權限夠不夠，以及 vault 和 bucket 有資料時 destroy 會怎樣，還是要照 [`docs/guides/cloud-verification-account-baseline.md`](../../../../docs/guides/cloud-verification-account-baseline.md) 在真實帳號確認。

## 怎麼跑

需要 Terraform、AWS CLI、`rsync`，以及 Docker 或 Podman 其中一個。Module 從 HCP private registry 下載，所以也要有 HCP token（見 [`docs/guides/consuming-modules.md`](../../../../docs/guides/consuming-modules.md)）。

```bash
./floci.sh run      # up → prepare → init → apply → verify → destroy
./floci.sh down     # 移除 Floci container
```

要停在中間看結果，就分段跑：`up`、`prepare`、`init`、`apply`、`verify`、`destroy`。Floci 的資料只放在記憶體，container 重啟就會清空；這時要先 `down`，再從 `up` 重跑。

Floci 固定用 port 4566。example6 的 Floci 還在跑的話，先在 `templates/example6/infra/floci/` 跑 `./floci.sh down`。

## `floci.sh` 做了什麼

1. 把 `../terraform` 複製到 `$TMPDIR/floci-account-baseline`（可以用 `FLOCI_WORK_DIR` 改位置），之後只動複本。複本放在 repo 外面，因為 `scripts/validate.sh` 會掃 `templates/` 底下所有的 `.tf`。
2. 每個 stack 加一個 `floci_override.tf`（內容見 `provider_override.tf.tmpl`），寫死假的 access key。就算 `AWS_ENDPOINT_URL` 漏設，請求也會因為驗證失敗被擋下，碰不到真實帳號。access key 用 12 位數的 `111111111111`，Floci 會把它當成帳號 ID 回傳，`allowed_account_ids` 的檢查才過得了。
3. 每個 stack 的 `envs/dev.tfbackend` 換成 Floci 裡的 S3，state key 沿用原本的值。

這個範本沒有 Lambda、ECS 或 ECR，Floci 不用另外啟動 container，所以不必掛 Docker 或 Podman 的 socket。

## verify 檢查什麼

| 項目 | 怎麼判斷 |
|---|---|
| apply 後再 plan 一次 | 每個 stack 都要沒有變更；只允許下面列出的 Floci 差異 |
| 跨 stack 契約 | 列出 `/baseline/dev` 底下的 SSM 參數 |
| CloudTrail | trail `baseline-dev-trail` 在記錄 |
| Config | recorder 在記錄 |
| GuardDuty | 有一個 detector |
| Security Hub | 已啟用 |
| S3 帳號層 public access block | 四項都是 `true` |
| 密碼政策 | 最短 14 碼 |
| EBS | 預設加密開著 |
| Backup | vault `baseline-dev-backup` 已經 lock |
| Budgets | 有一個 budget |

## Floci 驗不到的部分

### 複本裡改過的設定

| 檔案 | 改了什麼 | 原因 |
|---|---|---|
| `defaults/security.tf` | `imdsv2_default` 改成 `false` | Floci 2.4.0 的 `ModifyInstanceMetadataDefaults` 回 `UnsupportedOperation`。IMDSv2 的帳號預設值要在真實帳號驗證 |

### 第二次 plan 的已知差異

這筆差異直接呼叫 Floci 的 API 確認過，原因是 Floci 回傳的值跟 AWS 不同：

| 資源 | Floci 的行為 |
|---|---|
| `audit`：`module.config_recorder.aws_config_configuration_recorder.this` | `DescribeConfigurationRecorders` 不回傳 `recordingStrategy`，所以每次 plan 都想補上 |

### destroy 時從 state 移除、不刪除的資源

這兩個資源 Floci 建得起來、刪不掉。所以 `floci.sh destroy` 先把它們從 state 移除，`down` 時再跟 Floci 一起清掉：

| 資源 | 原因 |
|---|---|
| `detect`：`module.securityhub.aws_securityhub_account.this` | 不支援 `DisableSecurityHub` |
| `detect`：`module.inspector.aws_inspector2_enabler.this` | 不支援 Inspector2 的 `Disable` |

### 本來就驗不到的

- Floci 不會真的把 CloudTrail、Config 的 log 寫進 bucket，也不會照排程跑備份。所以 destroy 時 log bucket 是空的、vault 裡沒有 recovery point，每個 stack 都刪得掉。REFERENCE〈destroy〉說的「刪不掉」與「保護設定先被刪掉」，要在真實帳號照 runbook 第 8 項確認。
- GuardDuty、Security Hub、Inspector 不會產生 finding，finding 的 EventBridge 規則和告警送不送得出去，這裡看不出來。
- Floci 預設不檢查 IAM policy，所以 `iam` stack 與 KMS key policy 給的權限夠不夠，這裡看不出來。
- Organizations 模式（REFERENCE〈Organizations 模式〉）沒有測，它用到的 Config aggregator Floci 2.4.0 也不支援。範本沒用到的 Access Analyzer archive rule 同樣不支援。
- 費用、配額、各 region 能不能用，都要在真實帳號確認。

## 版本

Floci 固定在 `2.4.0`（2026-10-31），要換版本就設定 `FLOCI_IMAGE`。換版後，上面的已知差異和改過的設定都要重新確認。
