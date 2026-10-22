project             = "example"
env                 = "sit"
expected_account_id = "222222222222"
deploy_role_arn     = ""

services       = ["api", "worker", "import-extract", "import-load"]
agent_runtimes = ["agent"]

# Repository names are <project>-<image>, with no env in them. When two envs share one account, create the repositories
# in the first env and set this to true in the other.
adopt_existing = false
