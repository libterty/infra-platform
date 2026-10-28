project             = "example"
env                 = "sit"
expected_account_id = "222222222222"
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
alb_ingress = { prefix_list_ids = ["pl-58a04531"] }

# The bastion instance is created by the operation stack; the two must agree.
bastion_enabled = false

# Example of a peering to another account's VPC. The peer account must accept the request.
peering = {
  peer_vpc_id   = "vpc-0fedcba9876543210"
  peer_owner_id = "444444444444"
  peer_cidrs    = ["10.250.0.0/16"]
}
