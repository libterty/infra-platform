project             = "example"
env                 = "sit"
expected_account_id = "222222222222"

vpc_cidr = "10.31.0.0/20"
azs      = ["ap-northeast-1a", "ap-northeast-1c"]

# Flow logs go to the flow log bucket of the foundation stack.
flow_log = true
