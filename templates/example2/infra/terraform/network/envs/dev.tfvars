project             = "example"
env                 = "dev"
expected_account_id = "111111111111"
deploy_role_arn     = ""

vpc_cidr = "10.10.0.0/16"
azs      = ["ap-northeast-1a", "ap-northeast-1c"]

# per_az puts a NAT gateway in each AZ. none creates no NAT, and then more interface endpoints are needed than this stack creates.
nat_mode = "per_az"

bedrock_endpoints_enabled = true

# Placeholder: replace with the networks that may reach the ALB. 0.0.0.0/0 opens it to everyone, so write it only on purpose.
alb_ingress = { cidrs = ["203.0.113.0/24"] }

# The bastion instance is created by the operation stack; the two must agree.
bastion_enabled = true

peering = null
