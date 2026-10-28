project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

# Only the name lives here; the value comes from the environment and must match the origin verify secret:
#   export TF_VAR_origin_verify_header_value=<at least 16 characters>
# Same name as in api/envs/dev.tfvars.
origin_verify_header_name = "X-Origin-Verify"
waf_rate_limit_per_5min   = 2000
log_retention_days        = 30
