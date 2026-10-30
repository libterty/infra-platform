project             = "cicd"
env                 = "sit"
expected_account_id = "222222222222"

# Used only when the service and the function are created; the pipeline deploys every later version. Push this tag
# by hand to both repositories before the first apply:
#   docker push <account>.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-sit-api:bootstrap
#   docker push <account>.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-sit-fn:bootstrap
api_bootstrap_image_tag = "bootstrap"
fn_bootstrap_image_tag  = "bootstrap"

# Same value as app_port in loadbalancer/envs/sit.tfvars.
app_port = 8080

api_desired_count  = 2
log_retention_days = 90
