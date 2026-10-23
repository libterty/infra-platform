output "spans_log_group_name" {
  description = "Log group X-Ray writes spans to; it must exist after the first span arrives."
  value       = local.spans_log_group
}

output "indexing_percentage" {
  description = "Percentage of spans indexed by the Default indexing rule."
  value       = aws_xray_indexing_rule.default.rule[0].probabilistic[0].desired_sampling_percentage
}
