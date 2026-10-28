variable "origin_verify_header_name" {
  description = "Header CloudFront adds to origin requests. It must equal origin_verify_header_name in the loadbalancer stack; the value comes from TF_VAR_origin_verify_header_value."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]{1,64}$", var.origin_verify_header_name))
    error_message = "origin_verify_header_name must be 1-64 letters, digits or hyphens."
  }
}

variable "origin_verify_header_value" {
  description = "Secret value of the origin verify header, the same value the loadbalancer stack gets. Export TF_VAR_origin_verify_header_value; never write it in a tfvars file."
  type        = string
  sensitive   = true

  validation {
    condition     = nonsensitive(length(var.origin_verify_header_value) >= 16)
    error_message = "origin_verify_header_value must be at least 16 characters."
  }
}

variable "origin_read_timeout" {
  description = "Seconds CloudFront waits for the next bytes from the ALB. Above 60 needs a CloudFront quota increase; streaming responses must send something within it."
  type        = number
  default     = 60
}

variable "rate_limit_per_5min" {
  description = "Requests per client IP in five minutes above which the CloudFront WAF blocks. Only this WAF sees the real client IP."
  type        = number
  default     = 2000
}

variable "rate_limit_allowlist_cidrs" {
  description = "IPv4 CIDRs exempt from the rate limit only; they stay subject to every other WAF rule."
  type        = list(string)
  default     = []
}

variable "body_size_exempt_path_prefixes" {
  description = "Path prefixes exempt from the 8 KB body size limit. Keep it equal to the loadbalancer stack's list, or this WAF blocks what the ALB allows."
  type        = list(string)
  default     = ["/api/admin"]
}

variable "waf_log_retention_days" {
  description = "Retention of the WAF log group (in us-east-1)."
  type        = number
  default     = 14
}

variable "access_log_retention_days" {
  description = "Days CloudFront access logs are kept in the bucket."
  type        = number
  default     = 14
}
