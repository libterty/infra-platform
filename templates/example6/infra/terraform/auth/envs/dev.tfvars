project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

# Unique per region; change it when copying the template.
domain_prefix     = "example-dev-login"
local_dev_origins = ["http://localhost:5173"]
# Off in dev so the stack can be destroyed without an extra apply.
deletion_protection = false
