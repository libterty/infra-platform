# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "firehose_names" {
  description = "Firehose delivery stream 名稱，key 為 s3、opensearch。"
  value       = { s3 = module.firehose_s3.name, opensearch = module.firehose_opensearch.name }
}

output "rule_names" {
  description = "IoT rule 名稱。"
  value       = module.rules.rule_names
}
