output "database_names" {
  description = "建好的 database 名稱，由小到大排序。"
  value       = sort(keys(aws_glue_catalog_database.this))
}

output "database_arns" {
  description = "database 名稱對應 ARN 的 map。"
  value       = { for name, db in aws_glue_catalog_database.this : name => db.arn }
}
