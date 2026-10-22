# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
# eval_batch exists in dev only and is not published: the person who starts a batch job passes its ARN.
output "role_arns" {
  description = "Role ARN by role key."
  value       = { for k, m in module.role : k => m.arn }
}
