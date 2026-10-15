# The only place that builds model ARNs: iam-app grants exactly invoke_arns and never assembles model ARNs itself.
locals {
  # The foundation-model region is always "*": a system inference profile routes requests to other regions, so a fixed
  # region fails intermittently.
  model_base = {
    for k, m in var.models : k => {
      profile_id = m.inference_profile_prefix == null ? null : "${m.inference_profile_prefix}.${m.foundation_model_id}"
      invoke_arns = concat(
        m.inference_profile_prefix == null ? [] : ["arn:aws:bedrock:${var.aws_region}:${var.expected_account_id}:inference-profile/${m.inference_profile_prefix}.${m.foundation_model_id}"],
        ["arn:aws:bedrock:*::foundation-model/${m.foundation_model_id}"],
        # Not verified: whether "*" also covers the empty region that global profiles authorize against. Kept to be safe.
        m.inference_profile_prefix == "global" ? ["arn:aws:bedrock:::foundation-model/${m.foundation_model_id}"] : [],
      )
    }
  }

  tracked_models = {
    for k, m in var.models : k => {
      copy_from = m.inference_profile_prefix == null ? "arn:aws:bedrock:${var.aws_region}::foundation-model/${m.foundation_model_id}" : local.model_base[k].invoke_arns[0]
    } if m.tracked
  }

  models = {
    for k, m in var.models : k => {
      model_id    = m.tracked ? module.inference_profile[0].arns[k] : coalesce(local.model_base[k].profile_id, m.foundation_model_id)
      invoke_arns = concat(local.model_base[k].invoke_arns, m.tracked ? [module.inference_profile[0].arns[k]] : [])
    }
  }
}

module "inference_profile" {
  source = "../../../../../modules/bedrock-inference-profile"
  count  = length(local.tracked_models) > 0 ? 1 : 0

  name_prefix = local.name_prefix
  profiles    = local.tracked_models
}
