project             = "example"
env                 = "sit"
expected_account_id = "222222222222"
deploy_role_arn     = ""

engine_version    = "16.6"
db_instance_class = "db.r6g.large"
db_reader_count   = 1

# max_connections depends on the instance class, so this is a placeholder. Set it to about 80 percent of the
# max_connections of db_instance_class (read it with SHOW max_connections) whenever the class changes.
connections_threshold = 1400

redis = {
  "rate-limit" = { node_type = "cache.r7g.large" }
  "stream"     = { node_type = "cache.r7g.large", num_node_groups = 2 }
}
