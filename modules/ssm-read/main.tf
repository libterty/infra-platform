# Only insecure_value is read: every parameter written by ssm-publish is non-secret, and reading the sensitive attribute would taint all downstream values.
data "aws_ssm_parameter" "this" {
  for_each = toset(concat(values(var.strings), values(var.lists)))

  name = "${var.ssm_prefix}/${each.key}"
}
