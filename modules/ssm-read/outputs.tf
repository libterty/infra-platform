output "strings" {
  description = "String parameter values, keyed by local name."
  value       = { for name, path in var.strings : name => data.aws_ssm_parameter.this[path].insecure_value }
}

output "lists" {
  description = "StringList parameter values split on commas, keyed by local name."
  value       = { for name, path in var.lists : name => split(",", data.aws_ssm_parameter.this[path].insecure_value) }
}
