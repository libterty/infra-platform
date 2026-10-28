project             = "example"
env                 = "dev"
expected_account_id = "111111111111"
deploy_role_arn     = ""

vpc_cidr = "10.10.0.0/16"
azs      = ["ap-northeast-1a", "ap-northeast-1c"]

# per_az puts a NAT gateway in each AZ. none creates no NAT, and then more interface endpoints are needed than this stack creates.
nat_mode = "per_az"

bedrock_endpoints_enabled = true

# CloudFront (the edge stack) is the way in, so the ALB accepts the CloudFront origin-facing managed prefix list.
# pl-58a04531 is com.amazonaws.global.cloudfront.origin-facing in ap-northeast-1; the ID differs per region, so check it:
#   aws ec2 describe-managed-prefix-lists --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing
# A prefix list counts as its max entries against the rules-per-security-group quota, once per port (443 and 80), which
# is more than the default of 60: raise the quota before apply (see REFERENCE).
# 203.0.113.0/24 is a placeholder for the office, so dev can reach the ALB directly; it costs one more rule per port.
alb_ingress = {
  prefix_list_ids = ["pl-58a04531"]
  cidrs           = ["203.0.113.0/24"]
}

# The bastion instance is created by the operation stack; the two must agree.
bastion_enabled = true

peering = null
