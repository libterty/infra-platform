# 怎麼改 module、怎麼發版

結論：一個 commit 只動一個 module 目錄、message 照 Conventional Commits，合併到 `main` 之後 release-please 會為那個 module 開 release PR，合併 release PR 就打出 `<module>-v<semver>` tag 並更新 CHANGELOG。例外是兩批手動打的 tag：v1 的 19 個 `<module>-v0.1.0`，以及 LLM 增補動到的 10 個 `<module>-v0.1.1`，都由人在整體驗收通過的 commit 上手動打。步驟在最後兩節。

2026-10-21 起，push 到 `main` 就會跑 release-please；同一天第一次透過它發了 11 個版本（v3）。設定檔是 `release-please-config.json`、`.release-please-manifest.json`、`.github/workflows/release.yml`。release PR 是用 `GITHUB_TOKEN` 開的，GitHub 不會替它觸發 CI，所以合併前要自己看過 diff。

## 改一個 module

1. 開分支，只改一個 module 的目錄（例如 `modules/ecs-service/`）。release-please 依路徑判斷 commit 屬於哪個 module；如果一個 commit 動到兩個 module，它會同時寫進兩邊的 CHANGELOG。
2. 照 TDD 寫：先寫 `tests/` 的 run（至少一個因為條件不成立而失敗），再改實作到全過。每條 validation 正反兩個方向各一個 run。
3. 變數與 output 的 `description` 用台灣繁體中文，識別字、欄位名稱、列舉值與 `<name>` 這類樣式放進反引號；單一變數的約束、範圍、預設行為、相依條件寫進 description。`.tf` 與 `.tftest.hcl` 裡的註解與 `error_message` 只用英文，不放 icon；註解只寫程式碼看不出來的原因。`README.md`、`CHANGELOG.md` 用台灣繁體中文。
4. 介面或 description 有變，就重新產生 `README.md` 的輸入輸出表（`terraform-docs -c .terraform-docs.yml modules/<module>`，只改 `BEGIN_TF_DOCS`／`END_TF_DOCS` 之間），並同步改 `examples/`。表格不要手改，`scripts/validate.sh` 的 S11 會擋。
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

範本從 HCP registry 引用已發佈的版本（ADR-0004），不是 `main` 上的程式碼。module 與範本要一起改時分兩次：先合併 module 的 PR 並等 release-please 發版、HCP 讀到新版，再開範本的 PR（MINOR 以上要改 `version`）。順序反過來的話，範本的 PR 在 CI 跑 init 或 validate 時會失敗。

`modules/` 底下不放 `provider`、`backend`、`.terraform.lock.hcl`；module 之間不互相呼叫；不用 `enable_xxx` 開關，資源要不要建由相依的輸入有沒有給決定。

module 用到 aws 以外的 provider（例如 `eks-addons` 的 helm）時：

- 測試檔要為 `required_providers` 裡的每個 provider 宣告 `mock_provider`，`validate.sh` 的 S1 會檢查。只用 helm 的 module 只需要 `mock_provider "helm"`。
- module 附的本地 Helm chart 放在 `charts/<chart>/`。`validate.sh` 在有 `helm` 時跑 `helm lint` 與 `helm template`；CI 會裝 helm，本機沒裝就印一行提示後略過，所以改 chart 時最好本機也裝。
- module 附的程式碼（例如 `lb-traffic-breaker/lambda/`）的測試寫成 `test_*.py`，只用標準函式庫；`validate.sh` 在有 `python3` 時跑 unittest。

## semver：看消費端換版後 plan 會看到什麼

判斷標準是：既有消費端把 `ref` 換成新版、不改自己的程式碼，`terraform plan` 會看到什麼。

| 等級 | 定義 | 例子 | commit type |
|---|---|---|---|
| MAJOR | 消費端必須改程式碼，或 plan 出現 replace／destroy | 刪除或改名變數、output；新增沒有預設值的必填變數；收緊 validation；改 resource address 卻沒有 `moved`；改會觸發 replace 的預設值；提高 provider 大版本下限 | `feat!:` 或 body 寫 `BREAKING CHANGE:` |
| MINOR | 消費端不用改程式碼，plan 可能有 in-place 變更或新增資源 | 新增有預設值、且預設維持原行為的變數；新增 output；放寬 validation；調整告警門檻預設 | `feat:` |
| PATCH | 換版後 plan 零差異 | 修 bug 且不改介面；用 `moved` 重構 address；要讓 registry 顯示新的 description 或 README | `fix:` |
| 不發版 | 只進 `main`，等這個 module 下一次 `feat:`／`fix:` 一起發 | 改 README、測試、重構但不急著發 | `docs:`、`refactor:`、`test:`、`chore:` |

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
| `last-release-sha` | `86f438d…` | release-please 往回找 commit 時停在這裡，見下面說明 |

`last-release-sha` 是 release-please 接手前 `main` 的最後一個 commit。現有的 42 個 tag 都是手動打的，而且 2026-10-20 改寫過歷史，tag 所在的 commit 對不到原本的 PR。release-please 依路徑分 commit 時對不上這些 tag，會把已發布的 commit 也算進下一版：沒設這個值時，dry-run 顯示它會一次開 20 個錯的 release PR（例如 `kms-key 0.2.0`）。設了之後，它往回找到這個 commit 就停，只看之後的變更；找得到的 release 仍然照常當成上一版的邊界。這個值留著不影響之後由 release-please 自己發的版本：2026-10-21 發完 11 個版本後，它沒有替已發的 module 再開 release PR。

新增 module 時，`release-please-config.json` 的 `packages` 加一行並設 `"initial-version": "0.1.0"`，`.release-please-manifest.json` 不要加；`CHANGELOG.md` 只放 `# Changelog` 這一行標題。合併到 `main` 後 release-please 會開這個 module 的第一個 release PR，合併就打出 `<module>-v0.1.0` 並寫好 CHANGELOG。release-please 會把原本那行 `# Changelog` 降成 `## Changelog` 留在檔尾，第一次發版後開個 `chore` commit 刪掉（v3 的 8 個 module 就是這樣）。`README.md` 的 module 表也要加。新 module 的第一個 tag 出來後，照 [`hcp-registry-setup.md`](./hcp-registry-setup.md) §3 到 HCP 登記一次。v3 的 8 個 module 是第一批這樣發的；下面兩節手動打 tag 的做法只是當時的紀錄。

### 一個 PR 動到多個 module

用 merge commit 合併（不要 squash），每個 module 的 commit 才會各自進 CHANGELOG。PR 標題**不要**寫成 Conventional Commit 格式（例如 `feat(eks): ...`）：merge commit 的內文就是 PR 標題，release-please 會把它當成一個 feature，寫進每個被動到的 module 的 CHANGELOG（2026-10-22 v4 C1 發生過）。標題改用一般敘述，例如「v4 C1：EKS module」。已經發生的話，在重建 release PR 時把那一行刪掉。

### 同時有多個 release PR

每個 release PR 都改 `.release-please-manifest.json`，合併一個之後其他的會衝突，release-please 不會自己重建。一次處理一個：

```bash
p=35                                           # 要合併的 release PR
title="$(gh pr view "$p" --json title --jq .title)"   # chore(main): release <module> <version>
comp="$(awk '{print $(NF-1)}' <<<"$title")"; ver="$(awk '{print $NF}' <<<"$title")"
br="release-please--branches--main--components--${comp}"
git fetch origin main "$br"
git checkout -B "rp-${comp}" origin/main
git checkout "origin/${br}" -- "modules/${comp}/CHANGELOG.md"
jq --arg k "modules/${comp}" --arg v "$ver" '.[$k] = $v' .release-please-manifest.json >.m.tmp && mv .m.tmp .release-please-manifest.json
git add .release-please-manifest.json "modules/${comp}/CHANGELOG.md"
git diff --cached --stat                       # 只能有這兩個檔
git commit -m "chore(main): release ${comp} ${ver}"
git push -f origin "rp-${comp}:${br}"
gh pr merge "$p" --squash
```

合併後等 `main` 上的 Release run 跑完、`gh release view <module>-v<version>` 查得到，再做下一個。Release run 偶爾在建完 release 之後遇到 GitHub GraphQL 的暫時錯誤而變紅；tag 與 Release 都在、PR 標成 `autorelease: tagged` 就不用重跑。

tag 由 GitHub ruleset 保護 `*-v*`，不准刪除與移動。打錯了就發下一個 PATCH 版，不要改舊 tag。

## 第一次發版：手動打 19 個 `<module>-v0.1.0` tag

v1 發版時，`.release-please-manifest.json` 把 19 個 module 都登記成 `0.1.0`。release-please 會當成已經發過，不會自己產生 `<module>-v0.1.0`，所以第一個 tag 由 platform team 手動打，之後的版本才交給 release-please（設計文件 §3.5、決策 27）。

前提：整體驗收（implement-process 的 Phase 10）已通過；每個要發的 module 的 `CHANGELOG.md` 已經把這一版標題的「（未發布）」改成發版日期，而且那個 commit 已經在 GitHub 的 `main` 上。release-please 發版時會自己改 CHANGELOG，手動打 tag 就要人來改；19 個 `v0.1.0` 與 10 個 `v0.1.1` 當初漏了這一步，2026-10-20 才補上。

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

**push tag 是人做的事**，不要寫進任何腳本或 CI。確認上面的檢查都沒有輸出後，由 platform team 的人手動推。module 已經在 HCP 登記過的話，**一次最多推 3 個 tag**：GitHub 遇到一次 push 超過 3 個 tag 時不發 webhook，HCP 收不到新版本（補救方式見 [`hcp-registry-setup.md`](./hcp-registry-setup.md)〈之後的維護〉）。這一節的 19 個是在 HCP 登記之前推的，所以一次推完沒有問題：

```bash
git push origin $(git tag -l "*-v${VERSION}" | sed 's#^#refs/tags/#')
```

推完到 GitHub 的 tag 頁面確認 19 個都在。打錯了（例如打在錯的 commit）而且還沒推，用 `git tag -d <tag>` 刪掉重打；已經推上去就不要移動，照上面的規則發下一個 PATCH 版。

本 repo 已照這個迴圈在 `38e5f79` 打好 19 個 `<module>-v0.1.0` annotated tag。本 repo 是範例，不部署到 AWS（2026-10-15 決定）。

## 增補：手動打 10 個 `<module>-v0.1.1` tag

LLM 與 AgentCore 的增補（設計文件決策 37–54）動到 10 個 module：7 個新 module，加上 `rds`、`s3-bucket`、`iam-role`。照使用者決定（決策 54），這 10 個一律打 `v0.1.1`。`rds`、`s3-bucket`、`iam-role` 的變更照上面的 semver 表本該是 MINOR，只有這一版例外，之後照表走。其餘 16 個 module 沒有變，只有 `v0.1.0`；manifest 因此是 16 個 `0.1.0`、10 個 `0.1.1`。

理由同上一節：增補驗收的 commit 把這 10 個在 `.release-please-manifest.json` 登記成 `0.1.1`，release-please 會當成已經發過，所以 tag 由 platform team 手動打。v1 的 19 個 `<module>-v0.1.0` 留在 `38e5f79`，不移動。

前提：增補的整體驗收（implement-process 的 Phase 16）已通過，manifest 已經改好，每個要發的 module 的 CHANGELOG 標題已經從「（未發布）」改成發版日期（理由見上一節的前提），而且那個 commit 已經在 GitHub 的 `main` 上。

```bash
# 1. 回到增補驗收通過的那個 commit
git switch main
git pull --ff-only
commit="$(git rev-parse --verify 'HEAD^{commit}')"
git log -1 --format='%h %s' "$commit"     # 確認是驗收通過的那個 commit

# 2. 要打的 module 從 manifest 讀，不手寫；預期 10 個（變數不叫 modules：zsh 的 modules 是唯讀的內建變數）
VERSION="0.1.1"
mods="$(jq -r --arg v "$VERSION" 'to_entries[] | select(.value == $v) | .key | sub("^modules/"; "")' .release-please-manifest.json)"
echo "$mods" | wc -l                       # 預期 10

# 3. 確認舊 tag 還在、新 tag 都還沒有
git tag --points-at 28a8647 | wc -l        # 預期 19
git tag -l "*-v${VERSION}"                 # 預期沒有輸出

# 4. 打 tag
for m in $(echo "$mods"); do
  test -d "modules/${m}" || { echo "no such module: $m"; continue; }
  git tag -a "${m}-v${VERSION}" -m "${m} v${VERSION}" "$commit"
done

# 5. 本機檢查：這個 commit 上恰好 10 個；舊的 19 個沒動
git tag --points-at "$commit" | wc -l      # 預期 10
git tag -l "*-v${VERSION}" | wc -l         # 預期 10
git tag --points-at 28a8647 | wc -l        # 預期 19
```

push 一樣由人手動做，只推這 10 個：

```bash
git push origin $(git tag -l "*-v${VERSION}" | sed 's#^#refs/tags/#')
```

推完到 GitHub 的 tag 頁面確認 10 個都在、舊的 19 個沒變。打錯了而且還沒推，用 `git tag -d <tag>` 刪掉重打；已經推上去就不要移動，發下一個 PATCH 版。

本 repo 已照這個迴圈在 `74149bc` 打好 10 個 `<module>-v0.1.1` annotated tag。第一次是在本機打在 `52f954e`。因為之後的強化與 `iam-role` 的變更也要進同一版，所以在任何 push 之前就用 `git tag -d` 全部刪掉，改在 `74149bc` 重打；遠端從來沒有指向 `52f954e` 的 `v0.1.1` tag。
