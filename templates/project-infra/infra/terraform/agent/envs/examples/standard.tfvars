# Standard production: a system inference profile, a STANDARD guardrail, a Memory and tracing. Copy to
# envs/<env>.tfvars and adjust; this file is not applied by itself.
project             = "alpha"
env                 = "prod"
expected_account_id = "222222222222"

agent_runtimes = {
  assistant = {
    image_tag  = "0000000" # replace with the tag your CI pushed
    models     = ["chat"]
    memories   = ["conversation"]
    guardrails = ["safety"]
    tracing    = true
  }
}

models = {
  chat = { foundation_model_id = "anthropic.claude-sonnet-4-5-20250929-v1:0", inference_profile_prefix = "apac" }
}

# STANDARD evaluates languages other than English; CLASSIC lets them through unchecked.
guardrails = {
  safety = {
    blocked_input_message   = "This request cannot be processed."
    blocked_output_message  = "This answer cannot be shown."
    cross_region_profile_id = "apac.guardrail.v1:0"
    content_filters = {
      PROMPT_ATTACK = { input_strength = "HIGH", output_strength = "NONE" }
      HATE          = { input_strength = "HIGH", output_strength = "HIGH" }
    }
  }
}

memories = {
  conversation = { event_expiry_days = 30 }
}
