# Example: a ROOT private CA on. Use it with `stacks.sh dev pki plan -- -var-file=envs/examples/pki.tfvars`; the file
# has no tfbackend because it is not an environment. A general-purpose CA costs about 400 USD a month (first 30 days of
# the first CA in a region are free); the fleet stack registers it to IoT Core in SNI_ONLY mode.
project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

ca = {
  type = "ROOT"
  subject = {
    organization = "Example"
    country      = "JP"
  }
}
