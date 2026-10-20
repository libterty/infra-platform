project             = "example"
env                 = "dev"
expected_account_id = "111111111111"
deploy_role_arn     = ""

# Terraform owns the Runtime image tag: build and push the image, then change this and apply.
agent_image_tag = "0.1.0"

model_id = "apac.anthropic.claude-sonnet-4-5-20250929-v1:0"

# fake uses built-in test data. For http, also set backend_url.
backend_mode = "fake"

# Must equal the same value in the iam stack.
guardrail_cross_region_profile_id = "apac.guardrail.v1:0"
