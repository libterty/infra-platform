project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

point_in_time_recovery_days = 7
# Off in dev so the stack can be destroyed without an extra apply.
deletion_protection = false
