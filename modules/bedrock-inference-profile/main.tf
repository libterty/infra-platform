resource "aws_bedrock_inference_profile" "this" {
  for_each = var.profiles

  name        = "${var.name_prefix}-${each.key}"
  description = each.value.description

  model_source {
    copy_from = each.value.copy_from
  }

  tags = var.tags
}
