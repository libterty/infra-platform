variable "eval_batch_model_id" {
  description = "Bedrock model ID (without the inference profile prefix) that the eval-batch role may invoke. Only used when env is dev; leave empty elsewhere."
  type        = string
  default     = ""

  validation {
    condition     = var.env != "dev" || var.eval_batch_model_id != ""
    error_message = "eval_batch_model_id is required when env is dev, where the eval-batch role is created."
  }
}

variable "guardrail_cross_region_profile_id" {
  description = "Guardrail profile id the guardrails of the agent stack use. It must equal the same variable in the agent stack; check-ssm-contract.sh compares the tfvars."
  type        = string
  default     = "apac.guardrail.v1:0"

  validation {
    condition     = can(regex("^[a-z]+(-[a-z]+)?\\.guardrail\\.v[0-9]+:[0-9]+$", var.guardrail_cross_region_profile_id))
    error_message = "The profile id has the shape <area>.guardrail.v<major>:<minor>, for example apac.guardrail.v1:0."
  }
}
