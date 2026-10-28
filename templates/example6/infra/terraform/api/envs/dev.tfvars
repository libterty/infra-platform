project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

# Push this tag to the containerimage repository before applying.
api_image_tag            = "0.1.0"
api_reserved_concurrency = 10
api_throttling = {
  rate_limit  = 50
  burst_limit = 100
}
# Same name as in web/envs/dev.tfvars.
origin_verify_header_name = "X-Origin-Verify"
log_retention_days        = 30
