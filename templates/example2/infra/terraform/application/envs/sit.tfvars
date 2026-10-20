project             = "example"
env                 = "sit"
expected_account_id = "222222222222"
deploy_role_arn     = ""

# Terraform owns the image tags: build and push the images, then change these and apply.
api_image_tag    = "0.1.0"
worker_image_tag = "0.1.0"

cors_allow_origins = ["https://app.example.com"]

# vpc trusts the VPC only. Use vpc_and_cloudfront when a CloudFront distribution is the only way in; never any.
forwarded_allow_ips_trust = "vpc"

# Example of a capacity window: more api tasks on weekdays during the day.
api_scheduled_scaling = {
  weekday_peak = { schedule = "cron(0 1 ? * MON-FRI *)", min_capacity = 4, max_capacity = 10 }
}
