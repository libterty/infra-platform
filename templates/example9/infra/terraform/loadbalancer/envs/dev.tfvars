project             = "cicd"
env                 = "dev"
expected_account_id = "111111111111"

# Same value as app_port in application/envs/dev.tfvars.
app_port = 8080

# A dev ALB is rebuilt often.
deletion_protection = false
