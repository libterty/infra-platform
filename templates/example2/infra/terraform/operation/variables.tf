variable "bastion_enabled" {
  description = "Create the SSM bastion. It must equal bastion_enabled in the network stack, which opens the paths from the bastion to the Proxy and the caches; nothing checks it at plan time, check-ssm-contract.sh compares the tfvars."
  type        = bool
  default     = false
}

variable "bastion_instance_size" {
  description = "Instance type of the bastion; it must match the arm64 AMI the ec2-bastion module picks."
  type        = string
  default     = "t4g.nano"
}

variable "import_extract_image_tag" {
  description = "Image tag of the import-extract function. Terraform owns it: change it here and apply."
  type        = string

  validation {
    condition     = var.import_extract_image_tag != "latest"
    error_message = "Use an explicit tag, not latest."
  }
}

variable "import_load_image_tag" {
  description = "Image tag of the import-load function. Terraform owns it: change it here and apply."
  type        = string

  validation {
    condition     = var.import_load_image_tag != "latest"
    error_message = "Use an explicit tag, not latest."
  }
}

variable "import_extract_memory_size" {
  description = "Memory of import-extract in MB, 128 to 10240."
  type        = number
  default     = 1024

  validation {
    condition     = var.import_extract_memory_size >= 128 && var.import_extract_memory_size <= 10240
    error_message = "Lambda memory is 128 to 10240 MB."
  }
}

variable "import_extract_timeout" {
  description = "Timeout of import-extract in seconds, 1 to 900."
  type        = number
  default     = 300

  validation {
    condition     = var.import_extract_timeout >= 1 && var.import_extract_timeout <= 900
    error_message = "Lambda timeout is 1 to 900 seconds."
  }
}

variable "import_extract_reserved_concurrency" {
  description = "Reserved concurrency of import-extract. One keeps embedding calls from several uploads from competing for the model quota; null leaves it unreserved, 0 stops the function."
  type        = number
  default     = 1

  validation {
    condition     = var.import_extract_reserved_concurrency == null ? true : var.import_extract_reserved_concurrency >= 0
    error_message = "Reserved concurrency must be null or at least 0."
  }
}

variable "import_load_memory_size" {
  description = "Memory of import-load in MB, 128 to 10240."
  type        = number
  default     = 512

  validation {
    condition     = var.import_load_memory_size >= 128 && var.import_load_memory_size <= 10240
    error_message = "Lambda memory is 128 to 10240 MB."
  }
}

variable "import_load_timeout" {
  description = "Timeout of import-load in seconds, 1 to 900."
  type        = number
  default     = 300

  validation {
    condition     = var.import_load_timeout >= 1 && var.import_load_timeout <= 900
    error_message = "Lambda timeout is 1 to 900 seconds."
  }
}

variable "import_load_reserved_concurrency" {
  description = "Reserved concurrency of import-load; null leaves it unreserved, 0 stops the function."
  type        = number
  default     = null

  validation {
    condition     = var.import_load_reserved_concurrency == null ? true : var.import_load_reserved_concurrency >= 0
    error_message = "Reserved concurrency must be null or at least 0."
  }
}

variable "lambda_log_retention_days" {
  description = "Retention of the Lambda log groups."
  type        = number
  default     = 14
}

variable "import_expiration_days" {
  description = "Days the intermediate result under extracted/ is kept. Uploads under incoming/ are not expired."
  type        = number
  default     = 30
}
