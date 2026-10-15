project             = "alpha"
env                 = "dev"
expected_account_id = "111111111111"

# Services that send traces to X-Ray; empty means no service is traced. Names must be in containerimage services.
# Turning one on also needs adot_collector in application (see infra/README.md).
tracing = []
