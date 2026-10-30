project             = "cicd"
env                 = "sit"
expected_account_id = "222222222222"

vpc_cidr = "10.30.0.0/16"
azs      = ["ap-northeast-1a", "ap-northeast-1c"]

# single keeps one NAT gateway; per_az removes the single-AZ dependency at the cost of one more NAT gateway.
nat_mode = "single"
