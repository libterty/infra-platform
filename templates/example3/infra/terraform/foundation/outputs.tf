# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "secret_names" {
  description = "Secret name by key; put the key values here out of band, for example with the AWS CLI."
  value       = { for k, s in aws_secretsmanager_secret.this : k => s.name }
}
