project             = "cicd"
env                 = "sit"
expected_account_id = "222222222222"

repository = "example-org/example-app"
branch     = "main"

approval_required  = true
fn_deploy_strategy = "Canary10Percent5Minutes"
log_retention_days = 90
