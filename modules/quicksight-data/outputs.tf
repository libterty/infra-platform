output "data_source_arns" {
  description = "data source 的 ARN，key 是 `athena_sources` 與 `redshift_sources` 的 key。"
  value       = local.data_source_arns
}

output "data_set_arns" {
  description = "dataset 的 ARN，key 是 `datasets` 的 key。"
  value       = { for k, d in aws_quicksight_data_set.this : k => d.arn }
}

output "vpc_connection_arn" {
  description = "VPC connection 的 ARN；沒給 `vpc_connection` 時是 `null`。"
  value       = one(aws_quicksight_vpc_connection.this[*].arn)
}
