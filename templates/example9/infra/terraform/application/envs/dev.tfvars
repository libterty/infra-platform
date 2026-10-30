project             = "cicd"
env                 = "dev"
expected_account_id = "111111111111"

# Used only when the service and the function are created; the pipeline deploys every later version. Push this tag
# by hand to both repositories before the first apply:
#   docker push <account>.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-api:bootstrap
#   docker push <account>.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-fn:bootstrap
api_bootstrap_image_tag = "bootstrap"
fn_bootstrap_image_tag  = "bootstrap"

# Same value as app_port in loadbalancer/envs/dev.tfvars.
app_port = 8080

api_desired_count  = 1
log_retention_days = 30
