variable "kms_key_arn" {
  type        = string
  description = "加密 Glue Data Catalog 的客戶管理 KMS key ARN（symmetric），必填。catalog metadata（`SSE-KMS`）與 connection 密碼都用這把 key。**這是帳號加 region 層級的設定，每個帳號、每個 region 只能由一處呼叫**；開了之後，所有讀寫 catalog 的身分（包括同帳號其他專案）都要在 key policy 或自己的 IAM policy 取得這把 key 的 `kms:Decrypt`、`kms:Encrypt`、`kms:GenerateDataKey`。"

  validation {
    condition     = var.kms_key_arn != null && can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}
