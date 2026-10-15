project             = "alpha"
env                 = "prod"
expected_account_id = "222222222222"

# Services that send traces to X-Ray; empty means no service is traced. Names must be in containerimage services.
# Turning one on also needs adot_collector in application (see infra/README.md).
tracing = []

# What each service may call in the agent stack, for example
# { api = { runtimes = ["assistant"] } }. Services that are not listed get no Bedrock permission.
agent_access = {}
