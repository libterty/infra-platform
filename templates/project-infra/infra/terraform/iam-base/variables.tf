variable "agent_service_roles" {
  description = "AgentCore and Bedrock service roles to create, with a trust policy only: knowledge_base, gateway. iam-app attaches their permissions after the agent stack exists, and agent checks that the roles it needs are here. Empty by default."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for r in var.agent_service_roles : contains(["knowledge_base", "gateway"], r)])
    error_message = "agent_service_roles accepts knowledge_base and gateway."
  }
}
