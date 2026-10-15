project             = "alpha"
env                 = "dev"
expected_account_id = "111111111111"

services = ["api", "worker"]

# Copies of external images for environments without internet access, for example ["adot-collector"].
mirrored_images = []

# AgentCore Runtime names; each gets a repository <project>-<env>-agent-<name>. Empty means no Runtime (agent stack).
agent_runtimes = []
