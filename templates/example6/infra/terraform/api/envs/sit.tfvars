project             = "example"
env                 = "sit"
expected_account_id = "222222222222"

# Push this tag to the containerimage repository before applying.
api_image_tag            = "0.1.0"
api_reserved_concurrency = 50
api_throttling = {
  rate_limit  = 200
  burst_limit = 400
}
# Same name as in web/envs/sit.tfvars.
origin_verify_header_name = "X-Origin-Verify"
log_retention_days        = 90
