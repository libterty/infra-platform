project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

# Both VPNs are off: client_vpn and site_to_site default to null, and nothing is created.
# envs/examples/vpn.tfvars shows how to turn them on. Client VPN costs about 126 USD per month per environment,
# Site-to-Site about 35 USD (design section 10, estimate).
