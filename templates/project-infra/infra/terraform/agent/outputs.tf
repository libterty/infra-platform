# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "runtime_arns" {
  description = "AgentCore Runtime ARN by Runtime name."
  value       = { for r, m in module.runtime : r => m.runtime_arn }
}

output "corpus_bucket_names" {
  description = "Corpus bucket name by knowledge base key; upload the documents here, then start an ingestion job."
  value       = { for k, b in module.corpus_bucket : k => b.bucket_name }
}
