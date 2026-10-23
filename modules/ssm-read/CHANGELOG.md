# Changelog

## [0.1.1](https://github.com/libterty/infra-platform/compare/ssm-read-v0.1.0...ssm-read-v0.1.1) (2026-10-23)


### Bug Fixes

* **ssm-read:** rewrite the input and output descriptions in Chinese ([49818a6](https://github.com/libterty/infra-platform/commit/49818a612d63a7dce05730eb5d95a9ecd1a9eb6e))

## 0.1.0（2026-10-15）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 跟 `ssm-publish` 配對的讀取 module：給 `<stack>/<key>` 清單，回傳字串與清單。
- 只讀 `insecure_value`；`lists` 以逗號切回清單。
- 同一個 `<stack>/<key>` 出現在多個本地名稱時只讀一次。
- 參數不存在時 plan 直接失敗，沒有預設值。
- 輸出 `strings`（`map(string)`）、`lists`（`map(list(string))`），key 為本地名稱。
- 輸入檢查：`ssm_prefix` 格式、每個值須為 `<stack>/<key>`，規則與 `ssm-publish` 一致。
