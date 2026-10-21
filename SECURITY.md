# 安全政策

## 回報漏洞

安全問題請私下回報，不要開公開的 issue 或 PR。到這個 repo 的 Security 分頁，按 Report a vulnerability（[直接開啟](https://github.com/libterty/infra-platform/security/advisories/new)）填寫。這是 GitHub 的 private vulnerability reporting，內容只有你和 repo 維護者看得到。

例如：

- module 的預設值會讓資源公開、不加密，或 IAM 權限比文件寫的大。
- validation 擋不住文件說不允許的設定。
- CI workflow 或 `scripts/` 可能讓 token 或 secret 外洩。

## 支援的版本

每個 module 只修最新的 MINOR 版。各 module 的最新版看 [README 的 module 表](./README.md#module)，tag 格式是 `<module>-v<MAJOR>.<MINOR>.<PATCH>`。修正會發成該 module 的新版，舊的 MINOR 版不另外補。

範本（`templates/`）沒有版本號，以 `main` 上的內容為準。

## 回報時請附上

- 受影響的 module 與版本（tag），或範本的檔案路徑。
- 問題是什麼、可能造成什麼影響。
- 重現方式：最小的 module 呼叫（HCL），以及 `scripts/validate.sh` 的輸出或你看到的行為。
- 建議的修法，有的話。

不要附真實的 secret、token、帳號 ID、state 或含真實資源 ID 的 plan 輸出，請換成佔位值。

## 之後怎麼處理

維護者會在這份私下回報裡回覆、討論修法。修好並發版後，再公開這份 security advisory。這個 repo 沒有承諾固定的回應時間。
