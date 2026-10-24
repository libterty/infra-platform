# Example: a provisioned cluster instead of Serverless. Use it with
# `stacks.sh dev warehouse plan -- -var-file=envs/examples/provisioned.tfvars`; the file has no tfbackend because it is
# not an environment. Switching an existing env is blocked by guard.tf: follow the README runbook first.
project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

warehouse_mode = "provisioned"
provisioned = {
  # A single-node ra3.large is the smallest cluster; AWS does not recommend single-node for critical workloads.
  node_type                         = "ra3.large"
  number_of_nodes                   = 1
  automated_snapshot_retention_days = 7
  skip_final_snapshot               = false
}
