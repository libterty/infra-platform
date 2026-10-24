# Example: add the Redshift data source next to the Athena one. Use it with
# `stacks.sh dev bi plan -- -var-file=envs/examples/redshift.tfvars` after replacing the placeholders; the file has no
# tfbackend because it is not an environment.
project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

# The secret holds the username and password of a dedicated read-only database user and is created outside this repo
# (design D10). Host, port and database come from the warehouse stack; the VPC connection uses the data subnets, the
# quicksight security group and the iam-base quicksight-vpc role. The ARN below is a placeholder.
redshift_reader_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev-quicksight-reader-AbCdEf"

owner_principals  = ["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/data-owners"]
reader_principals = ["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/data-readers"]

datasets = {
  events = {
    table = "events"
    columns = [
      { name = "event_id", type = "STRING" },
      { name = "event_time", type = "DATETIME" },
    ]
  }
  # A table in Redshift: the schema is the one Spectrum or COPY loads into, not a Glue database.
  events_dw = {
    source = "redshift"
    schema = "public"
    table  = "events"
    columns = [
      { name = "event_id", type = "STRING" },
      { name = "event_time", type = "DATETIME" },
    ]
  }
}
