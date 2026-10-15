# PoC: HTTP only, so the network stack must have alb_ingress.https = false with a narrow source.
# Copy to envs/<env>.tfvars and adjust; this file is not applied by itself.
project             = "alpha"
env                 = "dev"
expected_account_id = "111111111111"

deletion_protection = false
