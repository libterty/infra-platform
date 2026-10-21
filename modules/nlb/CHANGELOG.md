# Changelog

## [0.2.0](https://github.com/libterty/infra-platform/compare/nlb-v0.1.0...nlb-v0.2.0) (2026-10-21)


### ⚠ BREAKING CHANGES

* **nlb:** the access_logs input is removed. Use log-delivery with module.nlb.nlb_arn as the source.

### Features

* **nlb:** drop the classic access_logs block ([70ec562](https://github.com/libterty/infra-platform/commit/70ec562df81d6b1cbeeaf09b74e0488d4d835861))

## 0.1.0 (2026-10-21)


### Features

* **nlb:** add Network Load Balancer module with weighted target groups ([5fc30d3](https://github.com/libterty/infra-platform/commit/5fc30d395d004e84831242a0eb33554b0ae024c5))
