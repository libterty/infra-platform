# 交付到客戶環境（FDE）

結論：客戶環境連不到我們的 HCP registry 或 GitHub 時，FDE 做三件事。用 `scripts/vendor-modules.sh` 把專案 repo 裡的 registry source（或釘好 tag 的 `git::` source）換成客戶 repo 內的 vendored 目錄；用 `terraform providers mirror` 把 provider 準備成離線鏡像；跟客戶約定哪些 stack 由客戶自管、客戶照 SSM 合約發布哪些 key。客戶環境跟範本假設不同的地方，開 issue 回報給 platform team，不在交付 repo 裡直接改 module。

## 輸入與輸出

| | 內容 |
|---|---|
| 輸入 | 一個已經引用好 module 的專案 repo：registry 寫法（`app.terraform.io/<org>/<module>/aws` 加 `version`），或 git 寫法（`git::https://github.com/<github-org>/<repo>.git//modules/<module>?ref=<module>-v<semver>`）。做法見 [`consuming-modules.md`](./consuming-modules.md) |
| 輸出 | 客戶 repo：`vendor/modules/<module>/`、`vendor/modules/VERSIONS`、改寫過 `source` 的 `.tf`、provider 鏡像、SSM 合約表（`infra/README.md`）、這份文件 |

`vendor-modules.sh` 只做「registry 或 `git::...?ref=<tag>` → vendored 相對路徑」這一個方向。範本的相對路徑換成 registry 或 `git::` 是專案 app team 複製範本時做的，不歸這支腳本。

## 1. vendoring：`scripts/vendor-modules.sh`

在本 repo（infra-platform）的 clone 裡執行，tag 要先 fetch 下來。module 的內容一律從本 repo 的 tag 取，不從 registry 下載；registry 上的版本 `0.1.1` 就是 tag `<module>-v0.1.1`。

### registry 寫法的專案

registry 寫法有版本範圍，`.tf` 裡看不出實際用哪一版，所以先在每個 stack `terraform init`，讓 Terraform 把解析到的版本寫進 `modules.json`，腳本照這份紀錄 vendoring。這一步要有 HCP token（`terraform login`），在準備交付物的機器上做，不是在客戶環境。

```bash
CUSTOMER_REPO=/path/to/customer-repo      # 必須是 git repo 的根目錄，而且沒有未提交的變更
PLATFORM_REGISTRY="app.terraform.io/<org>"
export TF_DATA_DIR=.terraform-vendor      # 單一層的目錄名稱；下面的 init 與腳本要用同一個值

# 0. init 產生的目錄必須被客戶 repo 的 .gitignore 忽略，否則腳本會當成未提交的變更而拒絕執行
git -C "$CUSTOMER_REPO" check-ignore -q "infra/terraform/x/${TF_DATA_DIR}/" \
  || echo "先在客戶 repo 的 .gitignore 加上 .terraform*/ 並 commit"

# 1. 每個 stack init 一次（不連 backend），解析版本
for d in "$CUSTOMER_REPO"/infra/terraform/*/; do
  terraform -chdir="$d" init -backend=false -input=false >/dev/null || echo "FAIL $d"
done

# 2. 從 modules.json 撈出 <module>=<tag>；同一個 module 解析出兩個版本時會出現兩行，腳本會以碼 1 拒絕
pairs="$(jq -r --arg reg "$PLATFORM_REGISTRY/" '
    .Modules[]
    | select(.Version and (.Source | ascii_downcase | startswith($reg | ascii_downcase)))
    | (.Source | split("/")[2]) as $m | "\($m)=\($m)-v\(.Version)"
  ' "$CUSTOMER_REPO"/infra/terraform/*/"$TF_DATA_DIR"/modules/modules.json | sort -u)"
echo "$pairs"

# 3. vendoring
cd <platform-repo>
git fetch --tags origin
# shellcheck disable=SC2086  # pairs 要拆成多個參數
scripts/vendor-modules.sh --registry "$PLATFORM_REGISTRY" "$CUSTOMER_REPO" $pairs

# 4. 清掉 init 產生的目錄，之後用不到
rm -rf "$CUSTOMER_REPO"/infra/terraform/*/"$TF_DATA_DIR"
unset TF_DATA_DIR
```

腳本改寫的是「`source` 等於 `<registry>/<module>/aws`，而且 `modules.json` 解析到的版本等於指定 tag」的 module 區塊：`source` 換成相對路徑，同一個區塊的 `version` 那一行刪掉（本地路徑不能有 `version`）。比對 host 與 namespace 不分大小寫。module 區塊是靠大括號的層數找的，字串、註解與 heredoc 裡的內容不算；有檔案的大括號對不起來時，腳本以碼 1 拒絕。`modules.json` 比同目錄的 `.tf` 舊（init 之後又改過 `.tf`）時不採用，那個目錄的區塊會列為 `not resolved`。

所有改動都先在暫存目錄準備好，全部 module 都處理完才寫進客戶 repo，所以結束碼 1 一定代表客戶 repo 沒有被改。只有改寫過的 `.tf` 會被寫回，其他檔案一個位元組都不動。

### git 寫法的專案

```bash
cd <platform-repo>
git fetch --tags origin

CUSTOMER_REPO=/path/to/customer-repo      # 必須是 git repo 的根目錄，而且沒有未提交的變更
PLATFORM_URL="https://github.com/<github-org>/<repo>.git"

# 從客戶 repo 的 .tf 撈出所有 <module>=<tag>
pairs="$(grep -rhoE --include='*.tf' '//modules/[a-z0-9-]+\?ref=[a-z0-9-]+-v[0-9]+\.[0-9]+\.[0-9]+' "$CUSTOMER_REPO" \
  | sed -E 's#^//modules/([a-z0-9-]+)\?ref=#\1=#' | sort -u)"
echo "$pairs"

# shellcheck disable=SC2086  # pairs 要拆成多個參數
scripts/vendor-modules.sh --url "$PLATFORM_URL" "$CUSTOMER_REPO" $pairs
```

兩種寫法混用的專案，`--url` 與 `--registry` 可以一起給，`pairs` 合併兩邊撈出來的結果。

### 腳本做的事

| 步驟 | 做法 |
|---|---|
| 檢查輸入 | module 名稱符合 `^[a-z][a-z0-9-]*$` 且是 `modules/` 底下的目錄；tag 符合 `<module>-v<MAJOR>.<MINOR>.<PATCH>`、前綴等於 module 名稱、在本 repo 存在；`--url` 必須是 `https://github.com/<org>/<repo>.git`；`--registry` 必須是小寫 host 加 namespace（例如 `app.terraform.io/acme`），而且 `TF_DATA_DIR` 是單一層的目錄名稱 |
| 檢查目標 | 必須是 git repo 的根目錄、工作目錄乾淨（含未追蹤的檔案）；`vendor`、`vendor/modules` 不得是 symlink；`--registry` 時讀得到的 `modules.json` 都要是合法 JSON |
| 取檔 | `git archive <tag> modules/<module>`，不 checkout、不執行 module 裡的任何東西；內容有 symlink 或 submodule 就拒絕 |
| 寫入 | 固定寫到 `vendor/modules/<module>/`，已經有就整個換掉 |
| 改寫 | `--url`：只改 `source` 的值完全等於 `git::<url>//modules/<module>?ref=<tag>` 的那一行。`--registry`：見上一節。換成相對路徑（例如 `../../../vendor/modules/vpc`），同一行後面的註解保留 |
| 記錄 | `vendor/modules/VERSIONS` 每個 module 一行：名稱、tag、commit SHA |

結束碼：

| 碼 | 意思 | 怎麼辦 |
|---|---|---|
| 0 | 完成 | 往下做檢查 |
| 1 | 輸入錯誤或目標不符合條件，**什麼都沒改** | 照訊息修正後重跑 |
| 3 | 完成，但有些 `source` 沒有改寫，清單印在 stderr：git 寫法是同一個 module、ref 不同；registry 寫法是解析到別的版本（`resolved to <版本>`）或沒有 init 過（`not resolved`） | `not resolved`：那個 stack 沒有 init 或 `TF_DATA_DIR` 不一致，補 init 後重跑。版本不同：同一個 module 在客戶 repo 裡用了兩個版本，先在專案 repo 統一版本，再重新交付；不要手動把那一行改成 vendored 路徑，會變成用錯版本的程式碼 |

同一個 module 在參數裡出現兩次（例如上面撈出兩個不同的 tag）會直接以碼 1 拒絕，這也是「版本不一致」的訊號。

跑完之後：

```bash
cd "$CUSTOMER_REPO"
git status --short                                                  # 只有 vendor/ 與改寫過的 .tf
grep -rnE --include='*.tf' 'source *= *"(git::|app\.terraform\.io/)' . | grep -v '^./vendor/'   # 預期沒有輸出
cat vendor/modules/VERSIONS
```

離線檢查客戶 repo 能 init、validate、test（在本 repo 執行，目標可以是客戶 repo 的根目錄，也可以只指到單一 stack 目錄）：

```bash
cd <platform-repo>
scripts/validate.sh "$CUSTOMER_REPO"
```

指到客戶 repo 根目錄時，`scripts/validate.sh` 會把路徑換算成本 repo 的對應位置再套用靜態規則：

| 客戶 repo 的路徑 | 套用的規則 |
|---|---|
| `vendor/modules/<module>/` | 跟本 repo 的 `modules/<module>/` 相同（S2 放行 `ssm-publish`、S3 放行 `ssm-read`、S4 放行 `iam-role`、`iam-role-policy`、`security-group`、`vpc-interface-endpoints`、`vpc`） |
| `infra/terraform/<stack>/` | 跟範本的 stack 相同（S4、S8 一律不准直接宣告 IAM、SG 或其他原生 resource；S5 比對客戶這幾個 stack 的 `common.tf` 彼此是否一致） |

stack 目錄跟本 repo 的範本 stack 一樣，用 `-lockfile=readonly` init，並且依目錄結構（有 `envs/<env>.tfvars` 與 `tests/tfvars/`、`envs/examples/*.tfvars` 與 `tests/examples/`）對 tfvars 再各跑一次 `terraform test`。要求客戶 repo 的 stack 放在 `infra/terraform/<stack>/`，vendored 的 module 放在 `vendor/modules/<module>/`（`vendor-modules.sh` 固定寫到這裡）；放在別處的目錄會被當成一般目錄，S2、S3 不放行。

確認沒問題之後在客戶 repo 裡 commit，commit message 帶上 `VERSIONS` 的內容，之後誰要追是哪個版本都查得到。

### 升版重新交付

專案 repo 升了某個 module 的 `version` 或 `ref` 之後（registry 寫法吃到新的 patch 版也算），客戶 repo 的那一行已經是 vendored 路徑，腳本找不到可以改的 `source`。做法是從專案 repo 重新產生交付內容：把專案 repo 的 `infra/` 同步到客戶 repo（覆蓋成 registry 或 `git::` 版本並 commit），照上面的步驟再跑一次（registry 寫法要重新 init）。腳本會整個換掉 `vendor/modules/<module>/` 並更新 `VERSIONS` 那一行。

## 2. provider 的離線鏡像：`terraform providers mirror`

這一步是在**準備交付物的機器**上跑，給客戶環境用；不是本 repo 的驗證流程，本 repo 的實作與 CI 不跑它。它只從 registry 下載 provider，不碰任何 AWS 帳號。

```bash
cd "$CUSTOMER_REPO"
for d in infra/terraform/*/; do
  terraform -chdir="$d" providers mirror \
    -platform=linux_amd64 -platform=darwin_arm64 \
    "$PWD/terraform-providers"
done
```

- `-platform` 列客戶實際會跑 terraform 的平台。
- 每個 stack 都有 `.terraform.lock.hcl`，鏡像裡的版本照 lock 檔；8 個 stack 的 provider 版本相同，鏡像只會有一份。
- `terraform-providers/` 要不要進客戶 repo，跟客戶談（檔案很大）；不進 repo 就另外交付。

客戶環境的 CLI 設定（`~/.terraformrc`，或用 `TF_CLI_CONFIG_FILE` 指到這個檔）：

```hcl
provider_installation {
  filesystem_mirror {
    path    = "/path/to/terraform-providers"
    include = ["registry.terraform.io/hashicorp/*"]
  }
  direct {
    exclude = ["registry.terraform.io/hashicorp/*"]
  }
}
```

設好之後在客戶環境 `terraform init` 不需要連 registry。這組設定只用在客戶環境；本 repo 禁止用 `TF_CLI_CONFIG_FILE` 指到本機鏡像（會弄壞 `.cache/plugins`）。

## 3. 客戶自管資源的 SSM 合約

跟客戶先談定每個 stack 由誰管，寫成一張表交給客戶：

| stack | 誰管 | 我們這邊的 `envs/<env>.tfbackend`、`envs/<env>.tfvars` |
|---|---|---|
| `network` | 例：客戶（模式 B） | 不放 |
| 其他 | 我們 | 放 |

- **模式 A**（客戶管 VPC、我們管 SG）：`network` 照跑，tfvars 改給 `existing = { vpc_id, subnet_ids }`。客戶 VPC 要開 `enable_dns_support` 與 `enable_dns_hostnames`，三個 tier 的 subnet 數量相同、AZ 順序一致（程式只檢查數量）。我們不碰路由、IGW、NAT、gateway endpoint、default SG；`network/nat` 發布 `{"mode":"external","ids":[]}`。
- **模式 B**（整個 stack 由客戶管）：我們的 repo 在那個環境不放這個 stack 的 tfbackend 與 tfvars，沒有檔案就無法 init。客戶照 `infra/README.md` 的 SSM 合約表，在 `/<project>/<env>/<stack>/<key>` 發布**全部** key，包括 JSON 值（`alb_https`、`db_proxy`、`data_access`、`nat`、`interface_endpoints`、`database`、`ecs_exec_<service>`、`tracing`）。路徑裡的 `<stack>` 照寫，即使客戶那邊沒有叫這個名字的東西。
- 客戶的部署 role 不能改 IAM 時，`iam-base` 與 `iam-app` 一定要用模式 B 交給客戶。
- 建議客戶給我們的部署 role 明確 Deny `ssm:PutParameter`、`ssm:DeleteParameter` 於客戶擁有的路徑。

交付前用客戶發布的值做一次檢查：客戶發布完之後，下游 stack 第一次 plan 就會讀那些 key，缺 key 會直接失敗（`ssm-read` 不給預設值），JSON 格式錯會在 `jsondecode` 失敗。這是好事，代表缺什麼在 plan 就看得到。

## 4. 客戶環境差異怎麼回報

FDE 不決定差異要不要收進 module，platform team 決定。遇到範本或 module 做不到的事，在本 repo 開 issue，內容包括：

| 欄位 | 寫什麼 |
|---|---|
| 客戶與環境 | 哪個客戶、哪個環境、哪個 stack |
| 現象 | plan／apply 的錯誤訊息原文，或缺少的功能 |
| 客戶的限制 | 例如「部署 role 明確 Deny `iam:Put*`」「VPC 沒有 NAT」「命名規範是 `[資源]-[應用]-[環境]-[區域]-[描述]-[序號]`」 |
| 消費端的呼叫方式 | 相關 module 呼叫的 HCL 與 tfvars（拿掉帳號與 secret） |
| 期望行為 | 希望 module 或範本怎麼做 |
| 目前的權宜做法 | 交付 repo 裡暫時怎麼處理 |

platform team 決定收進 module（通常是 MINOR）或留在專案。收進 module 之後，FDE 升版並重新交付，不要在客戶 repo 的 `vendor/modules/` 裡直接改：那裡的內容要能用 `VERSIONS` 的 tag 對回本 repo，改了就對不回去。
