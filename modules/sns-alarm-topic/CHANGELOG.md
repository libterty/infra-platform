# Changelog

## 0.1.0（未發布）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立一個 `aws_sns_topic`，名稱等於 `name`，tag 為輸入的 `tags` 加上 `Name`。
- 每個 `email_subscriptions` 建立一個 email 訂閱，重複的 email 只建一個。
- 可選 `kms_master_key_id`，拒絕 `alias/aws/sns`。
- 輸出 `topic_arn`、`topic_name`、`subscription_arns`。
- 不管 topic policy、不建 KMS key、不支援 Lambda、https、Slack、Chatbot 訂閱。
