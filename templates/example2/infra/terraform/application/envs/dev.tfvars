project             = "example"
env                 = "dev"
expected_account_id = "111111111111"
deploy_role_arn     = ""

# Terraform owns the image tags: build and push the images, then change these and apply.
api_image_tag    = "0.1.0"
worker_image_tag = "0.1.0"

cors_allow_origins = ["https://app.example.com"]

# vpc trusts the VPC only. Use vpc_and_cdn when a CloudFront distribution is the only way in; never any.
trusted_proxies = "vpc"

enable_execute_command = true
api_min_capacity       = 1
api_max_capacity       = 4
worker_min_capacity    = 1
worker_max_capacity    = 2
