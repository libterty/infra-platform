project             = "example"
env                 = "sit"
expected_account_id = "222222222222"
deploy_role_arn     = ""

vpc_cidr = "10.10.0.0/16"
azs      = ["ap-northeast-1a", "ap-northeast-1c"]

# per_az puts a NAT gateway in each AZ. none creates no NAT, and then more interface endpoints are needed than this stack creates.
nat_mode = "per_az"

bedrock_endpoints_enabled = true

# Placeholder: replace with the networks that may reach the ALB. 0.0.0.0/0 opens it to everyone, so write it only on purpose.
alb_ingress = { cidrs = ["203.0.113.0/24"] }

# The bastion instance is created by the operation stack; the two must agree.
bastion_enabled = false

# Example of a peering to another account's VPC. The peer account must accept the request.
peering = {
  peer_vpc_id   = "vpc-0fedcba9876543210"
  peer_owner_id = "444444444444"
  peer_cidrs    = ["10.250.0.0/16"]
}
