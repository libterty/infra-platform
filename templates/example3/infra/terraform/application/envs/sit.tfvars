project             = "example"
env                 = "sit"
expected_account_id = "222222222222"
deploy_role_arn     = ""

cors_allow_origins = ["https://app.example.com"]

# vpc trusts the VPC only. Use vpc_and_cdn when a CloudFront distribution is the only way in; never any.
trusted_proxies = "vpc"

