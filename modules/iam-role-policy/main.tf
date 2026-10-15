locals {
  role_name = element(split("/", var.role_arn), length(split("/", var.role_arn)) - 1)
}

resource "aws_iam_role_policy" "this" {
  for_each = var.policies

  name   = each.key
  role   = local.role_name
  policy = each.value
}
