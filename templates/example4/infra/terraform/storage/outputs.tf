# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "bucket_names" {
  description = "資料湖 bucket 名稱，key 為 raw、curated、athena_results、glue_assets。"
  value       = { for k, b in module.bucket : k => b.bucket_name }
}

output "database_names" {
  description = "Glue database 名稱，key 為 raw、curated。"
  value       = { for k, d in local.databases : k => d.name }
}

output "stream_name" {
  description = "Kinesis stream 名稱。"
  value       = module.stream.name
}

output "table_names" {
  description = "DynamoDB table 名稱，key 同 `tables`。"
  value       = { for k, t in module.table : k => t.table_name }
}
