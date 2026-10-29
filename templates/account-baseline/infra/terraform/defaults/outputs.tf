# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "access_analyzer_arn" {
  description = "IAM Access Analyzer（`ACCOUNT`）的 ARN。"
  value       = module.access_analyzer.arn
}
