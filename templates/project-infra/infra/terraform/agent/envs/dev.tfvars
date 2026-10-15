project             = "alpha"
env                 = "dev"
expected_account_id = "111111111111"

# Nothing is created until you add AgentCore Runtimes, models, guardrails, memories, knowledge bases or a gateway.
# Start from envs/examples/; a Runtime also needs containerimage agent_runtimes and network agent_runtimes.
agent_runtimes    = {}
models            = {}
guardrails        = {}
memories          = {}
knowledge_bases   = {}
agentcore_gateway = null
bedrock_invoke    = null
