project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

# No private CA (design D4): ca defaults to null, and nothing is created. Devices get certificates from AWS IoT through
# fleet provisioning. envs/examples/pki.tfvars shows how to turn a CA on; a general-purpose CA costs about 400 USD a month.
