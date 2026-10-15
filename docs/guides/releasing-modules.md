# 怎麼改 module、怎麼發版

結論：一個 commit 只動一個 module 目錄、message 照 Conventional Commits，合併到 `main` 之後 release-please 會為那個 module 開 release PR，合併 release PR 就打出 `<module>-v<semver>` tag 並更新 CHANGELOG。例外是兩批手動打的 tag：v1 的 19 個 `<module>-v0.1.0`，以及 LLM 增補動到的 9 個 `<module>-v0.1.1`，都由人在整體驗收通過的 commit 上手動打。步驟在最後兩節。

release-please 這條流程本機沒有、也沒有在 GitHub 上跑過，**未實測**；設定檔是 `release-please-config.json`、`.release-please-manifest.json`、`.github/workflows/release.yml`。

## 改一個 module

1. 開分支，只改一個 module 的目錄（例如 `modules/ecs-service/`）。release-please 依路徑判斷 commit 屬於哪個 module，一個 commit 動兩個 module，兩邊的 CHANGELOG 都會被寫進去。
2. 照 TDD 寫：先寫 `tests/` 的 run（至少一個因為條件不成立而失敗），再改實作到全過。每條 validation 正反兩個方向各一個 run。
3. `.tf` 與 `.tftest.hcl` 裡的註解、`description`、`error_message` 只用英文，不中英混雜，不放 icon；註解只寫程式碼看不出來的原因。`README.md`、`CHANGELOG.md` 用台灣繁體中文。
4. 介面有變就同步改 `README.md` 的輸入輸出表（目前手寫，之後改由 terraform-docs 產生）與 `examples/`。
5. 本機驗證，不需要 AWS 憑證：

```bash
scripts/validate.sh modules/ecs-service
```

6. commit message 照 Conventional Commits，scope 是 module 名稱：

```
feat(ecs-service): add sidecars for extra containers
fix(iam-role): reject allow statements with NotResource
```

不要手改 `CHANGELOG.md` 的版本段落，那是 release-please 產生的；PR 描述裡寫清楚消費端 plan 會看到什麼，release-please 會把 commit message 帶進 CHANGELOG。

`modules/` 底下不放 `provider`、`backend`、`.terraform.lock.hcl`；module 之間不互相呼叫；不用 `enable_xxx` 開關，資源要不要建由相依的輸入有沒有給決定。

## semver：看消費端換版後 plan 會看到什麼

判斷標準是：既有消費端把 `ref` 換成新版、不改自己的程式碼，`terraform plan` 會看到什麼。

| 等級 | 定義 | 例子 | commit type |
|---|---|---|---|
| MAJOR | 消費端必須改程式碼，或 plan 出現 replace／destroy | 刪除或改名變數、output；新增沒有預設值的必填變數；收緊 validation；改 resource address 卻沒有 `moved`；改會觸發 replace 的預設值；提高 provider 大版本下限 | `feat!:` 或 body 寫 `BREAKING CHANGE:` |
| MINOR | 消費端不用改程式碼，plan 可能有 in-place 變更或新增資源 | 新增有預設值、且預設維持原行為的變數；新增 output；放寬 validation；調整告警門檻預設 | `feat:` |
| PATCH | 換版後 plan 零差異 | 修 bug 且不改介面；用 `moved` 重構 address；改 description、README、測試 | `fix:`、`refactor:`、`docs:`、`test:` |

三條補充：

- MINOR 版會讓既有資源 in-place 更新時，CHANGELOG 要寫出 plan 會看到哪幾個資源、哪個屬性變了。
- ECS task definition 內容一變就會產生新 revision 並滾動部署。不算破壞性變更，但 CHANGELOG 要寫「會觸發一次部署」。
- 0.x 期間：`release-please-config.json` 設了 `bump-minor-pre-major`，破壞性變更只升 MINOR（`0.1.0` → `0.2.0`）。CHANGELOG 一樣要寫清楚，消費端照 CHANGELOG 改。設計文件 §7.3 的實環境驗證做完，才升 `v1.0.0`。

## release-please 流程

```
feat(ecs-service): ... 合併到 main
  → release.yml 觸發 release-please
  → 為 ecs-service 開一個 release PR（每個 module 各自一個 PR）：改 CHANGELOG.md 與 .release-please-manifest.json
  → 有權限的人審查並合併 release PR
  → release-please 打 tag ecs-service-v0.2.0
  → 通知消費端（MAJOR 或 0.x 的破壞性變更要另外通知）
```

| 設定 | 值 | 作用 |
|---|---|---|
| `include-component-in-tag` | `true` | tag 是 `<module>-v<semver>` |
| `separate-pull-requests` | `true` | 一個 module 一個 release PR，各自發版 |
| `bump-minor-pre-major` | `true` | 0.x 期間破壞性變更只升 MINOR |
| `release-type` | `terraform-module` | 每個 package 一個，`component` 等於目錄名 |

新增 module 時，`release-please-config.json` 的 `packages` 與 `.release-please-manifest.json` 各加一行，`README.md` 的 module 表也要加。

tag 由 GitHub ruleset 保護 `*-v*`，不准刪除與移動。打錯了就發下一個 PATCH 版，不要改舊 tag。

## 第一次發版：手動打 19 個 `<module>-v0.1.0` tag

`.release-please-manifest.json` 已經把 19 個 module 都登記成 `0.1.0`。release-please 會把它當成已經發過，不會自己產生 `<module>-v0.1.0`，所以第一個 tag 由 platform team 手動打，之後的版本才交給 release-please（設計文件 §3.5、決策 27）。

前提：整體驗收（implement-process 的 Phase 10）已通過，而且那個 commit 已經在 GitHub 的 `main` 上。

```bash
# 1. 回到整體驗收通過的那個 commit（通常就是 main 的最新 commit）
git switch main
git pull --ff-only
commit="$(git rev-parse --verify 'HEAD^{commit}')"
git log -1 --format='%h %s' "$commit"     # 確認是驗收通過的那個 commit

# 2. 確認還沒有任何 v0.1.0 tag，避免重複
git tag -l '*-v0.1.0'                      # 預期沒有輸出

# 3. 對 modules/ 底下每個目錄打一個 annotated tag（module 名稱從目錄讀，不手寫）
VERSION="0.1.0"
for d in modules/*/; do
  m="$(basename "$d")"
  git tag -a "${m}-v${VERSION}" -m "${m} v${VERSION}" "$commit"
done

# 4. 本機檢查：恰好 19 個，名稱都對得上 modules/ 的目錄，都指到同一個 commit
git tag -l "*-v${VERSION}" | wc -l         # 預期 19
for t in $(git tag -l "*-v${VERSION}"); do
  m="${t%-v${VERSION}}"
  test -d "modules/${m}" || echo "no such module: $t"
  test "$(git rev-parse "${t}^{commit}")" = "$commit" || echo "wrong commit: $t"
done                                        # 預期沒有輸出
```

**push tag 是人做的事**，不要寫進任何腳本或 CI。確認上面的檢查都沒有輸出後，由 platform team 的人手動推：

```bash
git push origin $(git tag -l "*-v${VERSION}" | sed 's#^#refs/tags/#')
```

推完到 GitHub 的 tag 頁面確認 19 個都在。打錯了（例如打在錯的 commit）而且還沒推，用 `git tag -d <tag>` 刪掉重打；已經推上去就不要移動，照上面的規則發下一個 PATCH 版。

本 repo 已照這個迴圈在 `28a8647` 打好 19 個 `<module>-v0.1.0` annotated tag。本 repo 是範例，不部署到 AWS（2026-10-15 決定）。

## 增補：手動打 9 個 `<module>-v0.1.1` tag

LLM 與 AgentCore 的增補（設計文件決策 37–54）動到 9 個 module：7 個新 module，加上 `rds`、`s3-bucket`。照使用者決定（決策 54），這 9 個一律打 `v0.1.1`。`rds`、`s3-bucket` 的變更照上面的 semver 表本該是 MINOR，只有這一版例外，之後照表走。其餘 17 個 module 沒有變，只有 `v0.1.0`。

理由同上一節：增補驗收的 commit 把這 9 個在 `.release-please-manifest.json` 登記成 `0.1.1`，release-please 會當成已經發過，所以 tag 由 platform team 手動打。v1 的 19 個 `<module>-v0.1.0` 留在 `28a8647`，不移動。

前提：增補的整體驗收（implement-process 的 Phase 16）已通過，manifest 已經改好，而且那個 commit 已經在 GitHub 的 `main` 上。

```bash
# 1. 回到增補驗收通過的那個 commit
git switch main
git pull --ff-only
commit="$(git rev-parse --verify 'HEAD^{commit}')"
git log -1 --format='%h %s' "$commit"     # 確認是驗收通過的那個 commit

# 2. 要打的 module 從 manifest 讀，不手寫；預期 9 個
VERSION="0.1.1"
modules="$(jq -r --arg v "$VERSION" 'to_entries[] | select(.value == $v) | .key | sub("^modules/"; "")' .release-please-manifest.json)"
echo "$modules" | wc -l                    # 預期 9

# 3. 確認舊 tag 還在、新 tag 都還沒有
git tag --points-at 28a8647 | wc -l        # 預期 19
git tag -l "*-v${VERSION}"                 # 預期沒有輸出

# 4. 打 tag
for m in $modules; do
  test -d "modules/${m}" || { echo "no such module: $m"; continue; }
  git tag -a "${m}-v${VERSION}" -m "${m} v${VERSION}" "$commit"
done

# 5. 本機檢查：這個 commit 上恰好 9 個；舊的 19 個沒動
git tag --points-at "$commit" | wc -l      # 預期 9
git tag -l "*-v${VERSION}" | wc -l         # 預期 9
git tag --points-at 28a8647 | wc -l        # 預期 19
```

push 一樣由人手動做，只推這 9 個：

```bash
git push origin $(git tag -l "*-v${VERSION}" | sed 's#^#refs/tags/#')
```

推完到 GitHub 的 tag 頁面確認 9 個都在、舊的 19 個沒變。打錯了而且還沒推，用 `git tag -d <tag>` 刪掉重打；已經推上去就不要移動，發下一個 PATCH 版。
