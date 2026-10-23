output "spans_log_group_name" {
  description = "X-Ray 寫入 span 的 log group，固定是 `aws/spans`；第一個 span 進來後就必須存在。"
  value       = local.spans_log_group
}

output "indexing_percentage" {
  description = "`Default` indexing rule 的建索引比例。"
  value       = aws_xray_indexing_rule.default.rule[0].probabilistic[0].desired_sampling_percentage
}
