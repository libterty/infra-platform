output "knowledge_base_id" {
  description = "Knowledge base ID."
  value       = aws_bedrockagent_knowledge_base.this.id
}

output "knowledge_base_arn" {
  description = "Knowledge base ARN."
  value       = aws_bedrockagent_knowledge_base.this.arn
}

output "data_source_ids" {
  description = "Data source IDs keyed by data_sources key."
  value       = { for k, d in aws_bedrockagent_data_source.this : k => d.data_source_id }
}
