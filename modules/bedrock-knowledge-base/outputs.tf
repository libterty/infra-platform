output "knowledge_base_id" {
  description = "KB id，給應用程式呼叫 `Retrieve` 與 `StartIngestionJob` 用。"
  value       = aws_bedrockagent_knowledge_base.this.id
}

output "knowledge_base_arn" {
  description = "KB ARN，給 IAM 權限用。"
  value       = aws_bedrockagent_knowledge_base.this.arn
}

output "data_source_ids" {
  description = "key 同 `data_sources` 的 map，值是 data source id。"
  value       = { for k, d in aws_bedrockagent_data_source.this : k => d.data_source_id }
}
