project             = "cicd"
env                 = "dev"
expected_account_id = "111111111111"

lifecycle_rules = {
  untagged_expire_days = 7
  keep_count           = 50
}
