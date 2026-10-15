# High traffic: three AZs, larger subnets, more endpoints, RDS Proxy.
# Copy to envs/<env>.tfvars and adjust; this file is not applied by itself.
project             = "alpha"
env                 = "prod"
expected_account_id = "222222222222"

vpc = {
  cidr = "10.40.0.0/16"
  azs  = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]

  subnets = {
    public = { type = "public", newbits = 8, netnum_base = 0 }
    app    = { type = "private", newbits = 4, netnum_base = 1 }
    data   = { type = "isolated", newbits = 10, netnum_base = 320 }
  }

  nat_mode = "per_az"
  flow_log = true
}

# Add bedrock-runtime when the services call Bedrock.
interface_endpoints = {
  services = ["ecr.api", "ecr.dkr", "logs", "secretsmanager", "kms", "ssm", "ssmmessages", "xray"]
}

services = {
  api    = { port = 8080, from_alb = true, data_access = ["db"] }
  worker = { port = 9000, callers = ["api"], data_access = ["db"] }
}

data_stores = {
  db = { port = 5432, proxy = true }
}

# CloudFront in front of the ALB: only its origin-facing prefix list may connect. Replace with the prefix list ID of your region.
alb_ingress = {
  https           = true
  prefix_list_ids = ["pl-58a04531"]
}
