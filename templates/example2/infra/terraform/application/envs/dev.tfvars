project             = "example"
env                 = "dev"
expected_account_id = "111111111111"
deploy_role_arn     = ""

# Terraform owns the image tags: build and push the images, then change these and apply.
api_image_tag    = "0.1.0"
worker_image_tag = "0.1.0"

cors_allow_origins = ["https://app.example.com"]

# CloudFront (the edge stack) is the way in, so the api also trusts the CloudFront origin-facing ranges for
# X-Forwarded-For. vpc trusts the VPC only; never any.
trusted_proxies = "vpc_and_cdn"

enable_execute_command = true
api_min_capacity       = 1
api_max_capacity       = 4
worker_min_capacity    = 1
worker_max_capacity    = 2
