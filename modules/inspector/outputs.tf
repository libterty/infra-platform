output "enabled_resource_types" {
  description = "啟用的掃描類型（排序過）。"
  value       = sort(var.resource_types)
}
