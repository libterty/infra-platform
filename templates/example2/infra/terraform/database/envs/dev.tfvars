project             = "example"
env                 = "dev"
expected_account_id = "111111111111"
deploy_role_arn     = ""

engine_version    = "16.6"
db_instance_class = "db.t4g.medium"
db_reader_count   = 0

# max_connections depends on the instance class, so this is a placeholder. Set it to about 80 percent of the
# max_connections of db_instance_class (read it with SHOW max_connections) whenever the class changes.
connections_threshold = 300

# A dev database is rebuilt often and holds nothing worth keeping.
deletion_protection = false
skip_final_snapshot = true

redis = {
  "rate-limit" = { node_type = "cache.t4g.small" }
  "stream"     = { node_type = "cache.t4g.small", num_node_groups = 1 }
}
