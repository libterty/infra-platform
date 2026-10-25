project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

vpc_cidr = "10.40.0.0/20"
azs      = ["ap-northeast-1a", "ap-northeast-1c"]

# Flow logs go to the flow log bucket of the foundation stack.
flow_log = true

# Interface endpoints: only "sagemaker.runtime" is accepted. Add it when the inference stack gets an endpoint that is
# called from inside the VPC; the endpoint is billed per hour in each AZ.
interface_endpoint_services = []
