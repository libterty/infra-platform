project             = "example"
env                 = "sit"
expected_account_id = "222222222222"
deploy_role_arn     = ""

# Only the header name is here. Export the value before plan or apply:
#   export TF_VAR_origin_verify_header_value=<at least 16 characters, the same value the CDN sends>
origin_verify_header_name  = "X-Origin-Verify"
origin_verify_host_headers = ["api.sit.example.com"]

# Placeholder: replace with the networks that are exempt from the WAF rate limit.
rate_limit_allowlist_cidrs = ["198.51.100.0/24"]
