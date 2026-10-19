# 把 module 登記到 HCP Terraform private registry

結論：platform team 一次性做四件事：開 HCP organization、連 GitHub、確認「從單一 repo 發佈多個 module」有開、把 `modules/` 底下每個 module 登記成 tag-based 發佈（Source Directory `modules/<module>`、Module Tag Prefix `<module>-v`）。之後發版流程不變，release-please 打的 tag 會自動變成 registry 上的新版本。決策背景見 [ADR-0004](../adr/0004-hcp-terraform-private-registry.md)。

HCP 的選單名稱會改版，下面寫的是 2026-10-19 查到的欄位名稱；畫面對不上時以 [HashiCorp 的發佈文件](https://developer.hashicorp.com/terraform/cloud-docs/registry/publish-modules)為準。

## 1. 前置條件

| 項目 | 要求 |
|---|---|
| HCP organization | 先開好，記下名稱，下文用 `<org>`。方案與價格以 HashiCorp 官方定價頁為準 |
| 登記的人 | 在 owners team，或所屬 team 有 **Manage private registry** 權限 |
| GitHub | 連 GitHub 的那個帳號對本 repo 要有 admin 權限，HCP 要建 webhook |
| tag | 每個 module 至少要有一個 `<module>-v<semver>` tag，tag-based 發佈才登記得起來 |

## 2. 一次性設定

1. 在 organization 設定裡確認 **Publish modules to your private registry from a single repository** 是開的（預設開）。沒開的話 HCP 會假設一個 repo 只放一個 module。
2. 在 organization 設定的 VCS providers 連上 GitHub。

## 3. 逐個登記 module

網頁和 API 都可以。第一個 module 建議在網頁上做，確認設定正確；其他的用 API 一次做完。

### 用 API 一次登記

官方 API 文件沒有寫 `tag-prefix` 與 `source-directory`，但 API 實際接受這兩個欄位（2026-10-19 用這個 repo 的 26 個 module 驗證過）。先在網頁上登記一個 module，再從它的設定讀出 GitHub App 的 installation ID：

```bash
ORG="<org>"
REPO="<github-org>/<repo>"
TOKEN="$(jq -r '.credentials["app.terraform.io"].token' ~/.terraform.d/credentials.tfrc.json)"   # terraform login 存的 user token；team／organization token 不能用來建 GitHub App 的 module
API="https://app.terraform.io/api/v2/organizations/${ORG}/registry-modules"

# 從已經在網頁上登記好的 module（例如 s3-bucket）讀 installation ID
INSTALL_ID="$(curl -sS -H "Authorization: Bearer $TOKEN" "${API}/private/${ORG}/s3-bucket/aws" \
  | jq -r '.data.attributes["vcs-repo"]["github-app-installation-id"]')"

for d in modules/*/; do
  m="$(basename "$d")"
  # 已經登記過的跳過
  curl -sfS -o /dev/null -H "Authorization: Bearer $TOKEN" "${API}/private/${ORG}/${m}/aws" && continue
  jq -n --arg m "$m" --arg repo "$REPO" --arg inst "$INSTALL_ID" '{data: {type: "registry-modules", attributes: {
      name: $m, provider: "aws", "registry-name": "private",
      "vcs-repo": {identifier: $repo, "display-identifier": $repo, "github-app-installation-id": $inst,
                   tags: true, "tag-prefix": ($m + "-v"), "source-directory": ("modules/" + $m)}}}}' \
    | curl -sS -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/vnd.api+json" -d @- "${API}/vcs" \
    | jq -r --arg m "$m" 'if .errors then "\($m) ERROR \(.errors)" else "\($m) \(.data.attributes.status)" end'
done
```

剛登記的 module 狀態是 `pending`，HCP 讀完 tag 之後變成 `setup_complete`，通常不到一分鐘。

### 在網頁上登記

要登記的清單從 `modules/` 目錄讀，不要手寫：

```bash
for d in modules/*/; do
  m="$(basename "$d")"
  printf '%-28s Source Directory: modules/%-28s Tag Prefix: %s-v\n' "$m" "$m" "$m"
done
```

每個 module 照這張表填：

| 欄位 | 值 |
|---|---|
| 來源 | 本 repo |
| 發佈方式 | Tag（不要選 Branch） |
| Module Tag Prefix | `<module>-v`，例如 `s3-bucket-v`。**不能空白**，空白會把 repo 裡所有 module 的 tag 都當成這個 module 的版本 |
| Source Directory | `modules/<module>` |
| Module Name | `<module>`，跟目錄名稱相同 |
| Provider Name | `aws` |

## 4. 檢查

在 HCP 網頁上，每個 module 的版本清單要跟 GitHub 的 tag 對得上：

```bash
git fetch --tags origin
for d in modules/*/; do
  m="$(basename "$d")"
  echo "$m: $(git tag -l "${m}-v*" | sed "s/^${m}-v//" | sort -V | tr '\n' ' ')"
done
```

再從消費端實際抓一次。下面在暫存目錄產生一個引用全部 module 的設定，用 `terraform get` 只下載 module：不裝 provider、不讀 backend，也不呼叫任何 AWS API。保險起見，再清掉本機的 AWS 憑證：

```bash
terraform login                     # 第一次用，token 會存到 ~/.terraform.d/credentials.tfrc.json
ORG="<org>"
tmp="$(mktemp -d)"
for d in modules/*/; do
  m="$(basename "$d")"
  printf 'module "%s" {\n  source  = "app.terraform.io/%s/%s/aws"\n  version = "~> 0.1.0"\n}\n\n' "${m//-/_}" "$ORG" "$m"
done >"${tmp}/main.tf"
env -u AWS_PROFILE -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN \
  AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null \
  terraform -chdir="$tmp" get >/dev/null && echo ok
jq -r '.Modules[] | select(.Version) | "\(.Key) \(.Version)"' "${tmp}/.terraform/modules/modules.json"

# 抽一個 module 確認下載的內容跟 tag 一致（以 s3-bucket 為例）
mkdir -p "${tmp}/tag" && git archive s3-bucket-v0.1.1 modules/s3-bucket | tar -x -C "${tmp}/tag"
diff -r "${tmp}/tag/modules/s3-bucket" "${tmp}/.terraform/modules/s3_bucket" && echo identical
rm -rf "$tmp"
```

`terraform get` 不會檢查 module 的必填變數，所以不必填任何輸入。`jq` 那行印出每個 module 解析到的版本，應該是各自最新的 `0.1.x`。

## 5. 消費端與 CI 的 token

| 在哪裡跑 | 做法 |
|---|---|
| 本機 | `terraform login`，用自己的帳號 |
| CI | 環境變數 `TF_TOKEN_app_terraform_io`，放在 CI 的 secret。用只能讀 registry 的 team token，不要用 owners team 或個人的 token |
| 客戶環境 | 不給我們的 token。FDE 用 `scripts/vendor-modules.sh --registry` 把 module 複製進客戶 repo（[`delivering-to-customer.md`](./delivering-to-customer.md)） |

## 之後的維護

| 情況 | 要做什麼 |
|---|---|
| 現有 module 發新版 | 不用做什麼。release-please 打 tag 之後，HCP 透過 webhook 發佈新版本；發版後在 HCP 上看一眼版本清單 |
| 新增 module | 第一個 tag 推上去之後，照第 3 節登記一次 |
| 刪除或改名 module | 在 HCP 上刪掉舊的登記；已經發佈的版本會跟著消失，先確認沒有消費端還在用 |
| HCP 抓不到 module | 消費端暫時退回 `git::...?ref=<tag>` 寫法（[`consuming-modules.md`](./consuming-modules.md) 的〈備案〉一節），tag 是同一批，內容相同 |
