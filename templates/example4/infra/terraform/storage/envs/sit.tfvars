project             = "example"
env                 = "sit"
expected_account_id = "222222222222"

# One example table for ingest bookkeeping; add a key per table (the SSM key is table_<key>_arn).
# On-demand billing, CMK encryption and deletion protection are fixed by the dynamodb-table module call.
tables = {
  ingest_state = {
    hash_key                    = "source_id"
    range_key                   = "ingested_at"
    attributes                  = { source_id = "S", ingested_at = "S" }
    ttl_attribute               = "expires_at"
    point_in_time_recovery_days = 35
  }
}
