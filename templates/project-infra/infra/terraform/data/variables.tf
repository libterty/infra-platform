variable "db" {
  description = "The database. null creates none and publishes {\"enabled\":false}. Set only the object that matches deployment (rds, aurora or serverless); alarm_config.connections_threshold is required for rds and aurora."
  type = object({
    deployment     = string # rds | aurora | aurora_serverless
    engine_version = string # PostgreSQL major.minor
    database_name  = string

    rds = optional(object({
      instance_class        = string
      allocated_storage     = optional(number)
      max_allocated_storage = optional(number)
      multi_az              = optional(bool)
      storage_type          = optional(string)
    }))
    aurora = optional(object({
      instance_class = string
      reader_count   = optional(number)
    }))
    serverless = optional(object({
      min_capacity = number
      max_capacity = number
      reader_count = optional(number)
    }))

    backup_retention_days = optional(number)
    deletion_protection   = optional(bool)
    skip_final_snapshot   = optional(bool)

    alarm_config = optional(object({
      connections_threshold = optional(number)
    }), {})
  })
  default = null
}
