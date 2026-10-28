project             = "example"
env                 = "sit"
expected_account_id = "222222222222"

# Only the name lives here; the value comes from the environment and must match the origin verify secret:
#   export TF_VAR_origin_verify_header_value=<at least 16 characters>
# Same name as in api/envs/sit.tfvars.
origin_verify_header_name = "X-Origin-Verify"
waf_rate_limit_per_5min   = 2000
log_retention_days        = 90
