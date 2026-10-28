project             = "example"
env                 = "sit"
expected_account_id = "222222222222"
deploy_role_arn     = ""

# Terraform owns the image tags: build and push the images, then change these and apply.
api_image_tag    = "0.1.0"
worker_image_tag = "0.1.0"

cors_allow_origins = ["https://app.example.com"]

# CloudFront (the edge stack) is the way in, so the api also trusts the CloudFront origin-facing ranges for
# X-Forwarded-For. vpc trusts the VPC only; never any.
trusted_proxies = "vpc_and_cdn"

# Example of a capacity window: more api tasks on weekdays during the day.
api_scheduled_scaling = {
  weekday_peak = { schedule = "cron(0 1 ? * MON-FRI *)", min_capacity = 4, max_capacity = 10 }
}
