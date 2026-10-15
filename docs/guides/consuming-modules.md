# 怎麼引用這個 repo 的 module

結論：用 `git::https://github.com/<org>/<repo>.git//modules/<module>?ref=<module>-v<semver>` 引用，一個 module 釘一個 tag。升版就是改 `ref` 的 PR：先讀 CHANGELOG，再跑 plan 看差異。從範本複製出去時，相對路徑要一次換成這個格式，下面有可以照抄的指令。

`<org>`、`<repo>` 還沒決定（設計文件 §9.3），下面一律用佔位符，用之前換成實際值。

## 寫法

```hcl
module "api" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ecs-service?ref=ecs-service-v0.1.0"

  # ...
}
```

| 部分 | 意思 |
|---|---|
| `git::https://github.com/<org>/<repo>.git` | 這個 repo |
| `//modules/ecs-service` | repo 內的子目錄，兩個斜線是 Terraform 的子目錄語法 |
| `?ref=ecs-service-v0.1.0` | tag，格式一律 `<module>-v<MAJOR>.<MINOR>.<PATCH>` |

- 同一個 root 裡引用多個 module 時，各自釘各自的 tag，不需要對齊版本。
- 每個 module 的輸入、輸出與範例在 `modules/` 底下各自的 `README.md`，例如 `modules/ecs-service/README.md`。

## 私有 repo 的認證

Terraform 自己沒有 registry token，抓 module 全靠 git 的憑證。

| 在哪裡跑 | 做法 |
|---|---|
| 本機 | `gh auth login` 之後跑 `gh auth setup-git`，讓 git 用 gh 的憑證；或改用 SSH 寫法 `git::ssh://git@github.com/<org>/<repo>.git//modules/ecs-service?ref=ecs-service-v0.1.0` |
| CI | 用對這個 repo 有唯讀權限的 GitHub App token 或 deploy key，不要用個人 token |

確認抓得到：

```bash
cd infra/terraform/foundation
terraform init -backend=false
```

認證錯誤的訊息通常是 `could not read Username for 'https://github.com'` 或 `Repository not found`。

## Git source 只能用 `ref` 釘死

Git source 不支援 `version = "~> 1.2"` 這種範圍，只能指定一個 tag（或 commit SHA）。

- 不會自動吃到 patch 版。每一次升版都是一個看得見的 PR。
- tag 理論上可以被移動。這個 repo 會用 GitHub ruleset 保護 `*-v*` tag；要求更嚴格的專案可以改釘 commit SHA，並在同一行註解寫對應的 tag：

```hcl
source = "git::https://github.com/<org>/<repo>.git//modules/ecs-service?ref=<commit-sha>" # ecs-service-v0.1.0
```

## 從範本複製出去：把相對路徑換成 git source

範本 `templates/project-infra/infra/` 在本 repo 裡用相對路徑 `../../../../../modules/<module>` 引用 module，這樣 tag 還沒打出來時也能驗證。複製到專案 repo 之後，每個 `source` 都要換成 git 格式。

一行的改法（以 `network/vpc.tf` 為例）：

```hcl
# 之前
source = "../../../../../modules/vpc"
# 之後
source = "git::https://github.com/<org>/<repo>.git//modules/vpc?ref=vpc-v0.1.0"
```

一次改完 9 個 stack 的指令（在專案 repo 的根目錄跑；macOS 與 Linux 的 `sed` 都適用）。先把每個 module 換成 `v0.1.0`，再把 LLM 增補動到的 10 個 module 改成 `v0.1.1`：7 個新 module 沒有 `v0.1.0`，範本的 `data` 用到 `rds-v0.1.1` 的輸出，`agent` 用到 `s3-bucket-v0.1.1` 的 `never_expire`，`iam-base` 的 agent 服務 role 用到 `iam-role-v0.1.1` 的 `trust.source_arn`，留在 `v0.1.0` 會 init 失敗或 plan 失敗。

```bash
PLATFORM_URL="https://github.com/<org>/<repo>.git"   # 換成實際的 org 與 repo

grep -rlE --include='*.tf' '"(\.\./){5}modules/' infra/terraform | while IFS= read -r f; do
  sed -E -i.bak "s#\"(\.\./){5}modules/([a-z0-9-]+)\"#\"git::${PLATFORM_URL}//modules/\2?ref=\2-v0.1.0\"#" "$f" && rm -f "$f.bak"
done

# LLM 增補動到的 module 只有 v0.1.1；之後 module 再發版，照下一節〈升版〉一個一個改
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

改完逐一 init，確認每個 tag 都抓得到：

```bash
for d in infra/terraform/*/; do
  (cd "$d" && TF_DATA_DIR=.terraform-check terraform init -backend=false -input=false >/dev/null && echo "ok $d") || echo "FAIL $d"
done
rm -rf infra/terraform/*/.terraform-check
```

這一步只做「相對路徑 → git source」。要把 git source 再換成客戶 repo 內的 vendored 目錄，是 FDE 用 `scripts/vendor-modules.sh` 做的另一件事，見 [`delivering-to-customer.md`](./delivering-to-customer.md)。

`ssm-inputs.tf` 裡 `source` 後面的英文註解（`After copying out of this repo, change to ...`）改完就可以刪掉。

## 升版

一次升一個 module，一個 PR：

1. 讀那個 module 的 `CHANGELOG.md`（在 tag 上讀：`https://github.com/<org>/<repo>/blob/<module>-v<新版>/modules/<module>/CHANGELOG.md`）。
2. 改 `ref`。下面的指令把所有 stack 裡的 `ecs-service` 換成新版，不會動到 `ecs-service-alarms`：

```bash
MODULE="ecs-service"
NEW="0.2.0"
grep -rlE --include='*.tf' "//modules/${MODULE}\?ref=" infra/terraform | while IFS= read -r f; do
  sed -E -i.bak "s#(//modules/${MODULE}\?ref=)${MODULE}-v[0-9]+\.[0-9]+\.[0-9]+#\1${MODULE}-v${NEW}#" "$f" && rm -f "$f.bak"
done
```

3. 每個用到它的 stack 跑 `terraform init -upgrade`（換了 ref，module 要重新抓）與 `plan`，把 plan 的摘要貼進 PR。
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

## 升級到真 registry 時消費端改什麼

之後換成 HCP Terraform private registry 或 boring-registry 時，module 程式碼不用改，消費端只改 `source` 並加上 `version`：

```hcl
# 之前
source = "git::https://github.com/<org>/<repo>.git//modules/ecs-service?ref=ecs-service-v1.2.0"

# 之後
source  = "<registry-host>/<namespace>/ecs-service/aws"
version = "~> 1.2"
```

那時就可以用版本範圍，不必每個 patch 都開 PR。觸發條件與兩個選項的取捨見設計文件 §3.6（README 的文件地圖有連結）。
