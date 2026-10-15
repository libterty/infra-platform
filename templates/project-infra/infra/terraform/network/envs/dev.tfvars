project             = "alpha"
env                 = "dev"
expected_account_id = "111111111111"

# PoC sizing (design section 5.11). The ALB has no certificate, so it is open only to a narrow CIDR.
vpc = {
  cidr = "10.20.0.0/20"
  azs  = ["ap-northeast-1a", "ap-northeast-1c"]

  # Each tier reserves slots for 4 AZs, so adding AZs later leaves existing subnets in place.
  subnets = {
    public = { type = "public", newbits = 6, netnum_base = 0 }
    app    = { type = "private", newbits = 4, netnum_base = 1 }
    data   = { type = "isolated", newbits = 7, netnum_base = 40 }
  }

  nat_mode = "single"
  flow_log = false
}

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

alb_ingress = {
  https = false
  cidrs = ["203.0.113.0/24"]
}
