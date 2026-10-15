# PoC: one small instance in a single AZ. Copy to envs/<env>.tfvars and adjust; this file is not applied by itself.
# The module cannot derive connections_threshold for rds and aurora (max_connections depends on the instance class), so set it.
project             = "alpha"
env                 = "dev"
expected_account_id = "111111111111"

db = {
  deployment     = "rds"
  engine_version = "16.4"
  database_name  = "app"

  rds = {
    instance_class = "db.t4g.micro"
    multi_az       = false
  }

  backup_retention_days = 1
  deletion_protection   = false

  alarm_config = {
    connections_threshold = 80 # a little under max_connections of db.t4g.micro
  }
}
