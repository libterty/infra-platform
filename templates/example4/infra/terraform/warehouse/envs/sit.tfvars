project             = "example"
env                 = "sit"
expected_account_id = "222222222222"

# Serverless by default (design K16): no charge while no query runs, and the monthly RPU-hour limit caps the spend.
warehouse_mode = "serverless"
serverless = {
  base_capacity         = 4
  max_capacity          = 16
  usage_limit_rpu_hours = 200
}
