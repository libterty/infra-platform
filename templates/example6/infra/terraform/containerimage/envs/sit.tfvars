project             = "example"
env                 = "sit"
expected_account_id = "222222222222"

lifecycle_rules = {
  untagged_expire_days = 7
  keep_count           = 50
}
