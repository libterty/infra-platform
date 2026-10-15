project             = "alpha"
env                 = "prod"
expected_account_id = "222222222222"

# Standard production sizing (design section 5.11): Serverless v2 at 2-16 ACU with one reader.
db = {
  deployment     = "aurora_serverless"
  engine_version = "16.4"
  database_name  = "app"

  serverless = {
    min_capacity = 2
    max_capacity = 16
    reader_count = 1
  }

  backup_retention_days = 14
  deletion_protection   = true
}
