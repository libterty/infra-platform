variable "ecs_exec_services" {
  description = "Services that get ECS Exec. Each gets the ssmmessages permissions on its task role, and application turns on enable_execute_command from the flag published here. Off by default: every enabled service can be entered with a shell."
  type        = list(string)
  default     = []
}

variable "tracing" {
  description = "Services that send traces to X-Ray. This is the single decision point for tracing: each listed service gets the X-Ray permissions on its task role, and application reads the list published here and adds the ADOT collector sidecar. Must be a subset of containerimage/services. Empty by default."
  type        = set(string)
  default     = []
}

variable "agent_access" {
  description = "Service => the AgentCore and Bedrock resources it may call, by the keys the agent stack publishes: runtimes, models, guardrails, knowledge_bases. This is the single decision point for what ECS services may call; application injects the matching ids. A service that is not listed gets no bedrock or bedrock-agentcore permission. Empty by default."
  type = map(object({
    runtimes        = optional(list(string), [])
    models          = optional(list(string), [])
    guardrails      = optional(list(string), [])
    knowledge_bases = optional(list(string), [])
  }))
  default = {}
}
