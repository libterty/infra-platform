## 摘要

<!-- 改了什麼、為什麼改 -->

## 改了哪些 module

<!-- 列出 module 名稱；沒動 module 就寫「無」 -->

## 消費端 plan 會看到什麼

<!-- 既有消費端換到新版、不改自己的程式碼，terraform plan 會看到什麼。判斷標準見 docs/guides/releasing-modules.md 的 semver 表 -->

- [ ] MAJOR：消費端必須改程式碼，或 plan 出現 replace／destroy（0.x 期間只升 MINOR，CHANGELOG 一樣要寫清楚）
- [ ] MINOR：消費端不用改程式碼，plan 可能有 in-place 變更或新增資源（寫出哪幾個資源、哪個屬性）
- [ ] PATCH：換版後 plan 零差異
- [ ] 不影響 module 版本（只改文件、範本、CI 或 scripts）

## 測試

- [ ] `scripts/validate.sh` 通過
- [ ] 新增的 validation 正反兩個方向各有一個 run
- [ ] 既有 tests 沒有修改

## 檢查清單

- [ ] 一個 commit 只動一個 module 目錄
- [ ] 沒有手改 `CHANGELOG.md` 的版本段落
- [ ] 沒有 secret、token、真實帳號 ID、state
- [ ] 新範本與新增或擴充的 module 裡，環境名稱只用 `dev`、`sit`
