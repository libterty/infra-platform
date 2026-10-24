project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

# No secret ARN: only the Athena data source is built (design D10). envs/examples/redshift.tfvars shows the Redshift source.
redshift_reader_secret_arn = null

# Placeholder principals. The QuickSight account, users and groups are managed outside Terraform; replace the account id
# and group names when copying the template.
owner_principals  = ["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/data-owners"]
reader_principals = ["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/data-readers"]

# One dataset on the curated database. The table is created by the Glue job, so adjust the name and columns to its output.
datasets = {
  events = {
    table = "events"
    columns = [
      { name = "event_id", type = "STRING" },
      { name = "event_time", type = "DATETIME" },
      { name = "payload", type = "STRING" },
    ]
  }
}
