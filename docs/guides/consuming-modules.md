# 怎麼引用這個 repo 的 module

結論：從 HCP Terraform private registry 引用，`source = "app.terraform.io/<org>/<module>/aws"` 加 `version = "~> 0.1.0"`。patch 版用 `terraform init -upgrade` 就吃得到；MINOR 以上的升版是改 `version` 的 PR，先讀 CHANGELOG 再跑 plan。從範本複製出去時，相對路徑要一次換成這個格式，下面有可以照抄的指令。拿不到 HCP token 的環境改用 git source，見最後一節〈備案〉。

`<org>` 是 HCP Terraform 的 organization 名稱，下面一律用佔位符，用之前換成實際值。為什麼改用 registry 見 [ADR-0004](../adr/0004-hcp-terraform-private-registry.md)。

## 寫法

```hcl
module "api" {
  source  = "app.terraform.io/<org>/ecs-service/aws"
  version = "~> 0.1.0"

  # ...
}
```

| 部分 | 意思 |
|---|---|
| `app.terraform.io` | HCP Terraform 的 registry host |
| `<org>` | HCP organization |
| `ecs-service` | module 名稱，跟本 repo `modules/` 底下的目錄名稱相同 |
| `aws` | provider，一律是 `aws` |
| `version = "~> 0.1.0"` | `>= 0.1.0, < 0.2.0`：吃得到 patch 版，不會跳到下一個 MINOR |

- 0.x 期間 MINOR 可能是破壞性變更（設計文件 §3.5），所以約束寫到 PATCH。module 到 1.0 之後改成 `~> 1.2`（`>= 1.2, < 2.0`）。
- 同一個 root 裡引用多個 module 時，各自寫各自的 `version`，不需要對齊。
- 每個 module 的輸入、輸出與範例在 `modules/` 底下各自的 `README.md`，例如 `modules/ecs-service/README.md`。
- registry 上的版本號就是 tag 去掉前綴：tag `ecs-service-v0.1.1` 是 `ecs-service` 的 `0.1.1`。

## 認證

| 在哪裡跑 | 做法 |
|---|---|
| 本機 | `terraform login`，token 存在 `~/.terraform.d/credentials.tfrc.json` |
| CI | 環境變數 `TF_TOKEN_app_terraform_io`，放在 CI 的 secret。用 platform team 發的唯讀 team token，不要用個人 token |

確認抓得到：

```bash
cd infra/terraform/foundation
terraform init -backend=false
```

沒登入或 token 錯誤時，`init` 會報找不到 module 或沒有權限。

## 版本範圍與 lock 檔

`.terraform.lock.hcl` 只鎖 provider，不鎖 module。module 的版本在 `init` 時解析：

- 已經 init 過的目錄，`init` 會沿用 `.terraform/modules/` 裡符合約束的版本；`init -upgrade` 才會換成範圍內最新的版本。
- CI 每次都是乾淨的目錄，會直接拿到範圍內最新的版本。所以新的 patch 版發佈之後，CI 的 plan 就會用到它。PATCH 依規則不改 plan，有差異就是 module 的 bug，回報給 platform team。
- 要完全固定版本（例如正式環境的變更凍結期），把 `version` 寫成精確版本 `"0.1.1"`。

實際解析到哪個版本記在 `<TF_DATA_DIR>/modules/modules.json`（預設 `.terraform/modules/modules.json`）：

```bash
jq -r '.Modules[] | select(.Version) | "\(.Key) \(.Version)"' .terraform/modules/modules.json
```

## 從範本複製出去：把相對路徑換成 registry

範本 `templates/project-infra/infra/` 在本 repo 裡用相對路徑 `../../../../../modules/<module>` 引用 module，這樣 tag 還沒打出來時也能驗證。複製到專案 repo 之後，每個 `source` 都要換成 registry 格式，並加上 `version`。

一行的改法（以 `network/vpc.tf` 為例）：

```hcl
# 之前
source = "../../../../../modules/vpc"
# 之後
source  = "app.terraform.io/<org>/vpc/aws"
version = "~> 0.1.0"
```

一次改完 9 個 stack 的指令（在專案 repo 的根目錄跑；macOS 與 Linux 的 `awk` 都適用）。每個 module 都寫 `~> 0.1.0` 就好：LLM 增補動到的 10 個 module（7 個新 module 加 `rds`、`s3-bucket`、`iam-role`）範圍內最新的是 `0.1.1`，`init` 會自己挑到，不必另外處理。

```bash
PLATFORM_REGISTRY="app.terraform.io/<org>"   # 換成實際的 organization

find infra/terraform -name '*.tf' -not -path '*/.terraform*' | while IFS= read -r f; do
  awk -v reg="$PLATFORM_REGISTRY" '
    match($0, /^[[:space:]]*source[[:space:]]*=[[:space:]]*"\.\.\/\.\.\/\.\.\/\.\.\/\.\.\/modules\/[a-z0-9-]+"/) {
      m = substr($0, RSTART, RLENGTH)
      sub(/^.*\/modules\//, "", m)
      sub(/"$/, "", m)
      indent = $0
      sub(/[^[:space:]].*$/, "", indent)
      print indent "source  = \"" reg "/" m "/aws\""
      print indent "version = \"~> 0.1.0\""
      next
    }
    { print }
  ' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
done
terraform fmt -recursive infra/terraform

grep -rnE --include='*.tf' 'source *= *"\.\./' infra/terraform   # 預期沒有輸出
grep -rhoE --include='*.tf' 'app\.terraform\.io/[^/]+/[a-z0-9-]+/aws' infra/terraform | sort -u | wc -l   # 預期 26
```

`ssm-inputs.tf` 裡 `source` 後面的英文註解（`After copying out of this repo, change to ...`）會跟著那一行一起被換掉，不用另外刪。

改完逐一 init，確認每個 module 都抓得到，並看解析到的版本：

```bash
for d in infra/terraform/*/; do
  (cd "$d" && TF_DATA_DIR=.terraform-check terraform init -backend=false -input=false >/dev/null && echo "ok $d") || echo "FAIL $d"
done
jq -r '.Modules[] | select(.Version) | "\(.Source) \(.Version)"' infra/terraform/*/.terraform-check/modules/modules.json | sort -u
rm -rf infra/terraform/*/.terraform-check
```

要把 module 再換成客戶 repo 內的 vendored 目錄，是 FDE 用 `scripts/vendor-modules.sh` 做的另一件事，見 [`delivering-to-customer.md`](./delivering-to-customer.md)。

## 升版

| 版本變化 | 消費端要做什麼 |
|---|---|
| PATCH | 不用改程式碼。`terraform init -upgrade` 之後跑 plan，預期沒有差異 |
| MINOR、MAJOR | 一次升一個 module，一個 PR：改 `version`（例如 `~> 0.1.0` → `~> 0.2.0`），照下面的步驟 |

1. 讀那個 module 的 `CHANGELOG.md`（在 tag 上讀：`https://github.com/<github-org>/<repo>/blob/<module>-v<新版>/modules/<module>/CHANGELOG.md`）。
2. 改 `version`。下面的指令把所有 stack 裡 `ecs-service` 的約束換掉，不會動到 `ecs-service-alarms`（awk 認的是 module 區塊裡的 `source`，不是字串前綴）：

```bash
MODULE="ecs-service"
NEW="~> 0.2.0"
grep -rlE --include='*.tf' "/${MODULE}/aws\"" infra/terraform | while IFS= read -r f; do
  awk -v src="/${MODULE}/aws\"" -v new="$NEW" '
    /^[[:space:]]*module[[:space:]]+"/ { in_block = 1; hit = 0; buf_n = 0 }
    in_block {
      buf[++buf_n] = $0
      if ($0 ~ /^[[:space:]]*source[[:space:]]*=/ && index($0, src) > 0) hit = 1
      if ($0 ~ /^}/) {
        for (k = 1; k <= buf_n; k++) {
          line = buf[k]
          if (hit && line ~ /^[[:space:]]*version[[:space:]]*=/) sub(/"[^"]*"/, "\"" new "\"", line)
          print line
        }
        in_block = 0
      }
      next
    }
    { print }
  ' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
done
```

3. 每個用到它的 stack 跑 `terraform init -upgrade` 與 `plan`，把 plan 的摘要貼進 PR。
4. 照下表判斷能不能直接合併：

| 版本變化 | plan 預期看到什麼 | 怎麼處理 |
|---|---|---|
| PATCH | 沒有差異 | 有差異就是 module 的 bug，回報給 platform team |
| MINOR | 可能有 in-place 更新或新增資源；CHANGELOG 會寫是哪些 | 對照 CHANGELOG，一致就合併。CHANGELOG 寫「會觸發一次部署」的（ECS task definition 變更），挑可以部署的時段 apply |
| MAJOR | 要改呼叫端程式碼，或有 replace／destroy | 照 CHANGELOG 的遷移步驟改，replace 的資源要先想清楚資料與停機 |

0.x 期間 MINOR 也可能是破壞性變更（設計文件 §3.5），一樣以 CHANGELOG 為準。

## 讀 CHANGELOG

每個 module 有自己的 `CHANGELOG.md`，由 release-please 依 commit 產生。重點看三種寫法：

- `BREAKING CHANGE`：要改呼叫端，或 plan 會出現 replace。
- in-place 變更：會列出 plan 會看到哪幾個資源、哪個屬性變了。
- 「會觸發一次部署」：ECS task definition 會產生新 revision。

## 備案：沒有 HCP token 時用 git source

registry 上的版本跟 GitHub 上的 tag 是同一批，內容相同。拿不到 HCP token（例如公開讀者、HCP 暫時抓不到）時，改用 git source：

```hcl
module "api" {
  source = "git::https://github.com/<github-org>/<repo>.git//modules/ecs-service?ref=ecs-service-v0.1.0"

  # ...
}
```

| 部分 | 意思 |
|---|---|
| `git::https://github.com/<github-org>/<repo>.git` | 這個 repo |
| `//modules/ecs-service` | repo 內的子目錄，兩個斜線是 Terraform 的子目錄語法 |
| `?ref=ecs-service-v0.1.0` | tag，格式一律 `<module>-v<MAJOR>.<MINOR>.<PATCH>` |

跟 registry 寫法的差別：

- 不能寫 `version`，也不支援範圍，只能用 `ref` 釘一個 tag（或 commit SHA）。每一次升版（包括 patch）都是改 `ref` 的 PR。
- 抓 module 靠 git 的憑證：本機 `gh auth login` 加 `gh auth setup-git`，或改用 SSH 寫法 `git::ssh://git@github.com/<github-org>/<repo>.git//modules/ecs-service?ref=ecs-service-v0.1.0`；CI 用對這個 repo 有唯讀權限的 GitHub App token 或 deploy key。認證錯誤的訊息通常是 `could not read Username for 'https://github.com'` 或 `Repository not found`。
- tag 由 GitHub ruleset 保護 `*-v*`；要求更嚴格的專案可以改釘 commit SHA，並在同一行註解寫對應的 tag：

```hcl
source = "git::https://github.com/<github-org>/<repo>.git//modules/ecs-service?ref=<commit-sha>" # ecs-service-v0.1.0
```

從範本複製出去時換成 git source 的指令。git source 沒有範圍，要逐個 module 釘到能用的 tag：先全部換成 `v0.1.0`，再把 LLM 增補動到的 10 個 module 改成 `v0.1.1`（7 個新 module 沒有 `v0.1.0`；範本的 `data` 用到 `rds-v0.1.1` 的輸出，`agent` 用到 `s3-bucket-v0.1.1` 的 `never_expire`，`iam-base` 的 agent 服務 role 用到 `iam-role-v0.1.1` 的 `trust.source_arn`，留在 `v0.1.0` 會 init 失敗或 plan 失敗）：

```bash
PLATFORM_URL="https://github.com/<github-org>/<repo>.git"   # 換成實際的 org 與 repo

grep -rlE --include='*.tf' '"(\.\./){5}modules/' infra/terraform | while IFS= read -r f; do
  sed -E -i.bak "s#\"(\.\./){5}modules/([a-z0-9-]+)\"#\"git::${PLATFORM_URL}//modules/\2?ref=\2-v0.1.0\"#" "$f" && rm -f "$f.bak"
done

for mv in bedrock-guardrail=0.1.1 bedrock-inference-profile=0.1.1 agentcore-runtime=0.1.1 agentcore-memory=0.1.1 \
          agentcore-gateway=0.1.1 log-delivery=0.1.1 bedrock-knowledge-base=0.1.1 rds=0.1.1 s3-bucket=0.1.1 \
          iam-role=0.1.1; do
  m="${mv%%=*}"; v="${mv#*=}"
  grep -rlE --include='*.tf' "//modules/${m}\?ref=" infra/terraform | while IFS= read -r f; do
    sed -E -i.bak "s#(//modules/${m}\?ref=)${m}-v[0-9]+\.[0-9]+\.[0-9]+#\1${m}-v${v}#" "$f" && rm -f "$f.bak"
  done
done

grep -rnE --include='*.tf' 'source *= *"\.\./' infra/terraform   # 預期沒有輸出
grep -rhoE --include='*.tf' 'ref=[a-z0-9-]+-v0\.1\.1' infra/terraform | sort -u   # 預期剛好是上面 10 個 module 的 v0.1.1
```

升版時改 `ref`（以 `ecs-service` 為例，不會動到 `ecs-service-alarms`）：

```bash
MODULE="ecs-service"
NEW="0.2.0"
grep -rlE --include='*.tf' "//modules/${MODULE}\?ref=" infra/terraform | while IFS= read -r f; do
  sed -E -i.bak "s#(//modules/${MODULE}\?ref=)${MODULE}-v[0-9]+\.[0-9]+\.[0-9]+#\1${MODULE}-v${NEW}#" "$f" && rm -f "$f.bak"
done
```

換了 `ref` 之後一樣要 `terraform init -upgrade` 再跑 plan。registry 與 git source 可以在同一個專案裡混用，但同一個 module 只用一種，`vendor-modules.sh` 才不會把它當成兩個版本。
