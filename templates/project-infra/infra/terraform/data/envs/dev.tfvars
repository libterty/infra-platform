project             = "alpha"
env                 = "dev"
expected_account_id = "111111111111"

# PoC sizing (design section 5.11): Serverless v2 at 0.5-4 ACU, no reader, no deletion protection so the sandbox can be torn down.
db = {
  deployment     = "aurora_serverless"
  engine_version = "16.4"
  database_name  = "app"

  serverless = {
    min_capacity = 0.5
    max_capacity = 4
  }

  backup_retention_days = 1
  deletion_protection   = false
}
