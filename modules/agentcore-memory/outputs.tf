output "memory_id" {
  description = "Memory id，給 Runtime 當 `memory_id`，以及放進 `MEMORY_ID_<KEY>` 環境變數。"
  value       = aws_bedrockagentcore_memory.this.id
}

output "memory_arn" {
  description = "Memory ARN，當 Runtime execution role 權限的 Resource。"
  value       = aws_bedrockagentcore_memory.this.arn
}

output "strategy_ids" {
  description = "key 同 `strategies` 的 map，值是 strategy id。"
  value       = { for k, s in aws_bedrockagentcore_memory_strategy.this : k => s.memory_strategy_id }
}
