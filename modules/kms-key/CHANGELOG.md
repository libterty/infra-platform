# Changelog

## [0.1.1](https://github.com/libterty/infra-platform/compare/kms-key-v0.1.0...kms-key-v0.1.1) (2026-10-23)


### Bug Fixes

* **kms-key:** rewrite the input and output descriptions in Chinese ([106f943](https://github.com/libterty/infra-platform/commit/106f9432e1cb70b2ed885de3a6c90044e3d96302))

## 0.1.0（2026-10-15）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立一把對稱式 customer managed key（`SYMMETRIC_DEFAULT`、`ENCRYPT_DECRYPT`、單一 region），固定開啟自動輪替。
- key policy 第一段固定是帳號 root 的 `kms:*`；`administrator_arns` 有給時多一段管理者 statement（不含加解密）；每個 `service_principals` 一段 statement。
- alias 為 `alias/<name>`。
- 輸出 `key_arn`、`key_id`、`alias_name`、`alias_arn`。
- 不做非對稱 key、multi-region key、外部金鑰材料、grant 管理，也不接受 `*` principal。
