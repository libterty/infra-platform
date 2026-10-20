# Changelog

## 0.1.0（2026-10-15）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 把 `strings` 以 `String`、`lists` 以 `StringList`（逗號串接）寫進 `<ssm_prefix>/<stack>/<key>`，tier 為 `Standard`，一律寫 `insecure_value`。
- 輸出 `names`、`arns`，key 為參數 key。
- 介面沿用 project-a 的 `ssm-publish`（`ssm_prefix`、`stack`、`strings`、`lists`）。
- 新增輸入檢查：`ssm_prefix` 與 `stack` 格式、key 為 snake_case、字串值 1–4096 字元、list 不可為空且元素不含逗號、`strings` 與 `lists` 的 key 不可重複。
