resource "aws_ssm_parameter" "string" {
  for_each = var.strings

  name           = "${var.ssm_prefix}/${var.stack}/${each.key}"
  type           = "String"
  tier           = "Standard"
  insecure_value = each.value
  description    = "Published by stack ${var.stack}. Managed by Terraform."
}

resource "aws_ssm_parameter" "list" {
  for_each = var.lists

  name           = "${var.ssm_prefix}/${var.stack}/${each.key}"
  type           = "StringList"
  tier           = "Standard"
  insecure_value = join(",", each.value)
  description    = "Published by stack ${var.stack}. Managed by Terraform."
}
