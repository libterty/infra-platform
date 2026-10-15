data "aws_caller_identity" "current" {}

resource "aws_bedrock_inference_profile" "this" {
  for_each = var.profiles

  name        = "${var.name_prefix}-${each.key}"
  description = each.value.description

  model_source {
    copy_from = each.value.copy_from
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}" })

  lifecycle {
    # System inference profile ARNs carry the caller's account; foundation-model ARNs have an empty account field.
    precondition {
      condition     = !strcontains(each.value.copy_from, ":inference-profile/") || try(split(":", each.value.copy_from)[4], "") == data.aws_caller_identity.current.account_id
      error_message = "An inference-profile copy_from must be in the current account."
    }
  }
}
