project             = "alpha"
env                 = "prod"
expected_account_id = "222222222222"

# Standard production sizing (design section 5.11).
vpc = {
  cidr = "10.30.0.0/19"
  azs  = ["ap-northeast-1a", "ap-northeast-1c"]

  subnets = {
    public = { type = "public", newbits = 5, netnum_base = 0 }
    app    = { type = "private", newbits = 3, netnum_base = 1 }
    data   = { type = "isolated", newbits = 7, netnum_base = 80 }
  }

  nat_mode = "per_az"
  flow_log = true
}

interface_endpoints = {
  services = ["ecr.api", "ecr.dkr", "logs", "secretsmanager", "kms"]
}

services = {
  api    = { port = 8080, from_alb = true, data_access = ["db"] }
  worker = { port = 9000, callers = ["api"], data_access = ["db"] }
}

data_stores = {
  db = { port = 5432, proxy = true }
}

alb_ingress = {
  https = true
  cidrs = ["0.0.0.0/0"]
}
