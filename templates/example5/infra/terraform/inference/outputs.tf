# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "endpoint" {
  description = "推論 endpoint 的狀態、名稱與 ARN（JSON）；沒有 endpoint 時是 `{\"enabled\":false}`。"
  value       = local.published_strings["endpoint"]

  # Only models of the ml stack's group, the one whose approvals CI follows, may be deployed.
  precondition {
    condition     = !local.enabled || try(split("/", var.model_package_arn)[1], "") == module.in.strings["model_package_group_name"]
    error_message = "model_package_arn must be a version of the model package group of the ml stack."
  }
}
