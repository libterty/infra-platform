output "memory_id" {
  description = "Memory id, used as memory_id by the Runtime and in MEMORY_ID_<KEY> environment variables."
  value       = aws_bedrockagentcore_memory.this.id
}

output "memory_arn" {
  description = "Memory ARN, used as the Resource of the Runtime execution role policy."
  value       = aws_bedrockagentcore_memory.this.arn
}

output "strategy_ids" {
  description = "Strategy ids keyed by the strategies key."
  value       = { for k, s in aws_bedrockagentcore_memory_strategy.this : k => s.memory_strategy_id }
}
