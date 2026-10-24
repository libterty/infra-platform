project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

# Design section 7.5: index age in days, cumulative. Cold migration needs the timestamp field.
ism = {
  warm_days       = 3
  cold_days       = 7
  delete_days     = 30
  timestamp_field = "@timestamp"
}

# Operations roles allowed to run UltraWarm and cold storage operations (IAM role ARNs); empty creates no mapping.
ultrawarm_manager_role_arns = []
cold_manager_role_arns      = []
