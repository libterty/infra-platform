# Changelog

## 0.1.0（2026-10-21）

初版。tag 在驗收後由人手動打。

- 建立一個 `aws_iam_openid_connect_provider`，給 Fargate 工作負載的 IRSA 用（設計文件 D7）。
- 輸入 `issuer_url`（只接受 `https://oidc.eks.<region>.amazonaws.com/id/<id>`）、`client_ids`（預設 `["sts.amazonaws.com"]`，至少一個）、`tags`。
- 輸出 `arn`、`issuer`（去掉 `https://`）。
- 不設定 `thumbprint_list`，由 AWS 用自己信任的 root CA 驗證。
