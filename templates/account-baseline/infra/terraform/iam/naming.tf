# Naming rule shared with the audit stack (applied later): the trail log group is /aws/cloudtrail/<name_prefix>.
# It does not exist when iam is applied, so its ARN is built from the name; audit must use exactly the same name.
locals {
  trail_log_group_name = "/aws/cloudtrail/${local.name_prefix}"
  trail_log_group_arn  = "arn:aws:logs:${var.aws_region}:${var.expected_account_id}:log-group:${local.trail_log_group_name}"
}
