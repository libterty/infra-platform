variable "nat_mode" {
  description = "Must equal nat_mode of the network stack (check-ssm-contract.sh compares the tfvars). per_az lets the system NetworkPolicies reach AWS APIs anywhere through NAT; none limits them to the interface endpoints in the app subnets."
  type        = string
  default     = "per_az"

  validation {
    condition     = contains(["per_az", "none"], var.nat_mode)
    error_message = "nat_mode must be per_az or none."
  }
}

variable "app_pool_cpu_limit" {
  description = "Total vCPU the app node pool may launch."
  type        = number
  default     = 100

  validation {
    condition     = var.app_pool_cpu_limit > 0
    error_message = "app_pool_cpu_limit must be greater than 0."
  }
}

variable "system_pool_cpu_limit" {
  description = "Total vCPU the system node pool may launch. It runs only the LB Controller and KEDA."
  type        = number
  default     = 16

  validation {
    condition     = var.system_pool_cpu_limit > 0
    error_message = "system_pool_cpu_limit must be greater than 0."
  }
}
