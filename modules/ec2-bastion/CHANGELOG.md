# Changelog

## 0.1.0（未發布）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立一台 `aws_instance`，AMI 用 `data "aws_ami"` 找最新的 Amazon Linux 2023（owner `amazon`，依 `architecture` 篩選）。
- 預設 `t4g.nano`、`arm64`、root volume 8 GiB。
- 固定設定，沒有開關：IMDSv2 必須（`http_tokens = "required"`）、`http_put_response_hop_limit = 1`、`associate_public_ip_address = false`、root volume 加密的 gp3，instance 與 root volume 都帶 tag。
- 沒有 `key_name` 輸入，只走 SSM Session Manager；`instance_profile_name` 必填。
- `security_group_ids` 至少一個。
- `instance_type` 與 `architecture` 不搭時在 plan 擋下（Graviton 家族名稱的世代數字後面有 `g`，例如 `t4g`、`c6gn`、`is4gen`）。這是依家族名稱判斷：舊的 `a1` 家族是 arm64 但不會被認出來。
- `lifecycle { ignore_changes = [ami] }`：新的 AMI 不會讓既有的 bastion 被取代。
- 輸出 `instance_id`、`private_ip`、`ami_id`。
- 不建 IAM、security group、Elastic IP；不支援 user data、額外的 EBS volume、自訂 KMS key。
