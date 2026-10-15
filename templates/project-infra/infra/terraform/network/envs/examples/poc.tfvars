# PoC: smallest footprint. Copy to envs/<env>.tfvars and adjust; this file is not applied by itself.
project             = "alpha"
env                 = "dev"
expected_account_id = "111111111111"

vpc = {
  cidr = "10.20.0.0/20"
  azs  = ["ap-northeast-1a", "ap-northeast-1c"]

  subnets = {
    public = { type = "public", newbits = 6, netnum_base = 0 }
    app    = { type = "private", newbits = 4, netnum_base = 1 }
    data   = { type = "isolated", newbits = 7, netnum_base = 40 }
  }

  nat_mode = "single" # use "none" when nothing in the VPC needs the internet
  flow_log = false
}

# No interface endpoints; only the S3 gateway endpoint of the vpc module.
interface_endpoints = {
  services = []
}

services = {
  api    = { port = 8080, from_alb = true, data_access = ["db"] }
  worker = { port = 9000, callers = ["api"], data_access = ["db"] }
}

data_stores = {
  db = { port = 5432, proxy = false }
}

# HTTP only: the ALB must not be open to the world without a certificate.
alb_ingress = {
  https = false
  cidrs = ["203.0.113.0/24"]
}
