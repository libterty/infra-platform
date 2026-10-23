project             = "example"
env                 = "dev"
expected_account_id = "111111111111"
deploy_role_arn     = ""

cors_allow_origins = ["https://app.example.com"]

# vpc trusts the VPC only. Use vpc_and_cdn when a CloudFront distribution is the only way in; never any.
trusted_proxies = "vpc"

api_min_capacity    = 1
api_max_capacity    = 4
worker_min_capacity = 1
worker_max_capacity = 2
