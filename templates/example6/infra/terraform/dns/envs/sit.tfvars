project             = "example"
env                 = "sit"
expected_account_id = "222222222222"

# Delegate this subdomain from the parent zone by hand after the first apply (NS record with the name_servers output).
domain_name = "sit.example.com"
