project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

vpc_cidr = "10.30.0.0/20"
azs      = ["ap-northeast-1a", "ap-northeast-1c"]

# Flow logs go to the flow log bucket of the foundation stack.
flow_log = true
