project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

# Delegate this subdomain from the parent zone by hand after the first apply (NS record with the name_servers output).
domain_name = "dev.example.com"
