project             = "example"
env                 = "sit"
expected_account_id = "222222222222"

# Design section 7.5: index age in days, cumulative. Cold migration needs the timestamp field.
ism = {
  warm_days       = 7
  cold_days       = 30
  delete_days     = 90
  timestamp_field = "@timestamp"
}

# Operations roles allowed to run UltraWarm and cold storage operations (IAM role ARNs); empty creates no mapping.
ultrawarm_manager_role_arns = []
cold_manager_role_arns      = []
