project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

# Serverless by default (design K16): no charge while no query runs, and the monthly RPU-hour limit caps the spend.
warehouse_mode = "serverless"
serverless = {
  base_capacity         = 4
  max_capacity          = 8
  usage_limit_rpu_hours = 100
}
