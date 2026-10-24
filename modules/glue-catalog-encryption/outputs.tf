output "catalog_id" {
  description = "套用這份加密設定的 Data Catalog ID（就是帳號 ID）。"
  value       = aws_glue_data_catalog_encryption_settings.this.id
}
