variable "eval_batch_model_id" {
  description = "Bedrock model ID (without the inference profile prefix) that the eval-batch role may invoke. Only used when env is dev; leave empty elsewhere."
  type        = string
  default     = ""

  validation {
    condition     = var.env != "dev" || var.eval_batch_model_id != ""
    error_message = "eval_batch_model_id is required when env is dev, where the eval-batch role is created."
  }
}
