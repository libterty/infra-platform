output "policy_names" {
  description = "Names of the attached inline policies."
  value       = keys(aws_iam_role_policy.this)
}

output "role_name" {
  description = "Name of the role the policies are attached to."
  value       = local.role_name
}
