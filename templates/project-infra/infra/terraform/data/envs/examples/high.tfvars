# High traffic: provisioned Aurora with two readers. Copy to envs/<env>.tfvars and adjust; this file is not applied by itself.
# Nobody has measured this sizing yet; treat it as a starting point and load test it.
# connections_threshold is required for aurora and rds because max_connections depends on the instance class.
project             = "alpha"
env                 = "prod"
expected_account_id = "222222222222"

db = {
  deployment     = "aurora"
  engine_version = "16.4"
  database_name  = "app"

  aurora = {
    instance_class = "db.r7g.xlarge"
    reader_count   = 2
  }

  backup_retention_days = 14
  deletion_protection   = true

  alarm_config = {
    connections_threshold = 2500 # check against max_connections of your instance class
  }
}
