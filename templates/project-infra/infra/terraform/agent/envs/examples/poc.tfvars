# PoC: one Runtime in the VPC calling one model on demand. Copy to envs/<env>.tfvars and adjust; this file is not applied
# by itself. The Runtime also needs containerimage agent_runtimes = ["assistant"] and network agent_runtimes.
project             = "alpha"
env                 = "dev"
expected_account_id = "111111111111"

agent_runtimes = {
  assistant = {
    image_tag = "0000000" # replace with the tag your CI pushed
    models    = ["chat"]
  }
}

models = {
  chat = { foundation_model_id = "anthropic.claude-sonnet-4-5-20250929-v1:0" }
}
