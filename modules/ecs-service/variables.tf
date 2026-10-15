variable "name" {
  type        = string
  description = "Service name; also the task family, log group suffix and target group name prefix."

  validation {
    # Max 26: the target group name is "<name>-<port>" and AWS caps it at 32 chars.
    condition     = can(regex("^[a-z][a-z0-9-]{1,25}$", var.name))
    error_message = "name must be 2-26 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "cluster_arn" {
  type        = string
  description = "ECS cluster ARN, from the ecs-cluster module."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:ecs:[a-z0-9-]+:[0-9]{12}:cluster/[A-Za-z0-9_-]+$", var.cluster_arn))
    error_message = "cluster_arn must be a full ECS cluster ARN."
  }
}

variable "image" {
  type        = string
  description = "Image reference with an explicit tag or digest."

  validation {
    condition     = can(regex("^[^\\s:@]+(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}|@sha256:[a-f0-9]{64})$", var.image)) && !endswith(var.image, ":latest")
    error_message = "image must carry an explicit tag (not latest) or a sha256 digest."
  }
}

variable "cpu" {
  type        = number
  default     = 512
  description = "Task CPU units."
}

variable "memory" {
  type        = number
  default     = 1024
  description = "Task memory in MiB; must pair with cpu."

  validation {
    condition = contains(lookup({
      "256"  = [512, 1024, 2048]
      "512"  = [1024, 2048, 3072, 4096]
      "1024" = range(2048, 8193, 1024)
      "2048" = range(4096, 16385, 1024)
      "4096" = range(8192, 30721, 1024)
    }, tostring(var.cpu), []), var.memory)
    error_message = "cpu/memory must be a supported Linux Fargate pair (256-4096 CPU units)."
  }
}

variable "cpu_architecture" {
  type        = string
  default     = "ARM64"
  description = "ARM64 or X86_64; must match the image."

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64."
  }
}

variable "container_port" {
  type        = number
  default     = null
  description = "Required when load_balancer or service_connect is set; null for workers without a port."

  validation {
    condition     = var.container_port == null ? true : (var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port)
    error_message = "container_port must be an integer from 1 to 65535."
  }

  validation {
    condition     = var.container_port != null ? true : (var.load_balancer == null && var.service_connect == null)
    error_message = "container_port is required when load_balancer or service_connect is set."
  }
}

variable "environment" {
  type        = map(string)
  default     = {}
  description = "Plain environment variables."
}

variable "secrets" {
  type        = map(string)
  default     = {}
  description = "Env var name => Secrets Manager or SSM SecureString ARN (Secrets Manager may append :json-key::)."

  validation {
    condition     = alltrue([for v in values(var.secrets) : can(regex("^arn:aws[a-z-]*:(secretsmanager|ssm):", v))])
    error_message = "Every secret must be a Secrets Manager or SSM parameter ARN."
  }
}

variable "execution_role_arn" {
  type        = string
  description = "Task execution role ARN, created by the caller (iam-base stack)."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", var.execution_role_arn))
    error_message = "execution_role_arn must be an IAM role ARN."
  }
}

variable "task_role_arn" {
  type        = string
  description = "Task role ARN, created by the caller (iam-app stack)."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", var.task_role_arn))
    error_message = "task_role_arn must be an IAM role ARN."
  }
}

variable "network" {
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  description = "Subnets and security groups, both created by the caller (network stack)."

  validation {
    condition     = length(distinct(var.network.subnet_ids)) >= 2 && length(var.network.security_group_ids) >= 1
    error_message = "Give at least two distinct subnets (different AZs) and one security group."
  }
}

variable "capacity_provider_strategy" {
  type = list(object({
    capacity_provider = string
    weight            = optional(number, 1)
    base              = optional(number, 0)
  }))
  default     = [{ capacity_provider = "FARGATE" }]
  description = "Capacity provider strategy of the service."
}

variable "desired_count" {
  type        = number
  default     = 2
  description = "Initial task count. The service ignores later changes; the autoscaling target owns capacity."
}

variable "autoscaling" {
  type = object({
    min_capacity = number
    max_capacity = number
    policy       = optional(string, "target_tracking")
    target_tracking = optional(object({
      cpu_percent         = optional(number, 60)
      requests_per_target = optional(number) # ALBRequestCountPerTarget
      scale_in_cooldown   = optional(number, 300)
      scale_out_cooldown  = optional(number, 60)
    }), {})
    step = optional(object({
      cpu_scale_out_threshold    = optional(number, 70)
      cpu_scale_in_threshold     = optional(number, 40)
      memory_scale_out_threshold = optional(number, 70)
      memory_scale_in_threshold  = optional(number, 50)
      scale_out_step_size        = optional(number, 10)
      scale_out_cooldown         = optional(number, 180)
      scale_in_cooldown          = optional(number, 300)
    }), {})
  })
  default     = null
  description = "null keeps a fixed task count of desired_count."

  validation {
    condition = var.autoscaling == null ? true : (
      contains(["target_tracking", "step"], var.autoscaling.policy) &&
      var.autoscaling.min_capacity >= 1 &&
      var.autoscaling.max_capacity >= var.autoscaling.min_capacity
    )
    error_message = "policy must be target_tracking or step, and 1 <= min_capacity <= max_capacity."
  }

  validation {
    condition = var.autoscaling == null ? true : (
      var.desired_count >= var.autoscaling.min_capacity && var.desired_count <= var.autoscaling.max_capacity
    )
    error_message = "desired_count must be between autoscaling.min_capacity and autoscaling.max_capacity."
  }

  validation {
    condition = var.autoscaling == null ? true : (
      var.autoscaling.target_tracking.requests_per_target == null ? true : (
        var.load_balancer == null ? false : var.load_balancer.alb_arn_suffix != null
      )
    )
    error_message = "autoscaling.target_tracking.requests_per_target needs load_balancer.alb_arn_suffix."
  }
}

variable "load_balancer" {
  type = object({
    # Mode 1: an existing target group.
    target_group_arn = optional(string)
    # Mode 2: the module creates the target group and listener rule.
    listener_arn  = optional(string)
    vpc_id        = optional(string)
    priority      = optional(number)
    host_headers  = optional(list(string), [])
    path_patterns = optional(list(string), [])
    health_check = optional(object({
      path                = optional(string, "/health")
      matcher             = optional(string, "200")
      interval            = optional(number, 10)
      timeout             = optional(number, 5)
      healthy_threshold   = optional(number, 3)
      unhealthy_threshold = optional(number, 3)
    }), {})
    # Both modes: required by requests_per_target and alarms.
    alb_arn_suffix = optional(string)
  })
  default     = null
  description = "null attaches no load balancer. Set exactly one of target_group_arn or listener_arn."

  validation {
    condition = var.load_balancer == null ? true : (
      (var.load_balancer.target_group_arn != null) != (var.load_balancer.listener_arn != null)
    )
    error_message = "Set exactly one of target_group_arn or listener_arn."
  }

  validation {
    condition = var.load_balancer == null ? true : (
      var.load_balancer.listener_arn == null ? true : (
        var.load_balancer.vpc_id != null && var.load_balancer.priority != null &&
        length(var.load_balancer.host_headers) + length(var.load_balancer.path_patterns) > 0
      )
    )
    error_message = "listener_arn mode needs vpc_id, priority and at least one host_headers or path_patterns entry."
  }
}

variable "health_check_grace_period_seconds" {
  type        = number
  default     = 180
  description = "Applied only when load_balancer is set; the service gets null otherwise."
}

variable "container_health_check" {
  type = object({
    command      = list(string)
    interval     = optional(number, 10)
    timeout      = optional(number, 5)
    retries      = optional(number, 3)
    start_period = optional(number, 60)
  })
  default     = null
  description = "Container health check; null sets none."
}

variable "service_connect" {
  type = object({
    namespace_arn = string
    dns_name      = optional(string) # null uses var.name
  })
  default     = null
  description = "Service Connect registration; null disables it."
}

variable "sidecars" {
  type = list(object({
    name               = string
    image              = string
    essential          = optional(bool, false)
    command            = optional(list(string))
    cpu                = optional(number) # CPU units reserved inside the task size
    memory_reservation = optional(number) # MiB, soft limit inside the task size
    environment        = optional(map(string), {})
    secrets            = optional(map(string), {}) # env name => Secrets Manager or SSM ARN
    port_mappings = optional(list(object({
      container_port = number
      protocol       = optional(string, "tcp")
    })), [])
    health_check = optional(object({
      command      = list(string)
      interval     = optional(number, 10)
      timeout      = optional(number, 5)
      retries      = optional(number, 3)
      start_period = optional(number, 10)
    }))
    app_depends_on    = optional(string) # START | HEALTHY | COMPLETE | SUCCESS; null = app does not wait
    log_stream_prefix = optional(string) # null uses the sidecar name
  }))
  default     = []
  description = "Extra containers in the task. Empty keeps the task definition identical to a single-container task."

  validation {
    condition = alltrue([for s in var.sidecars : can(regex("^[a-z][a-z0-9-]{0,62}$", s.name))]) && (
      length(distinct([for s in var.sidecars : s.name])) == length(var.sidecars)
    ) && !contains([for s in var.sidecars : s.name], "app")
    error_message = "Sidecar names must match ^[a-z][a-z0-9-]{0,62}$, be unique, and must not be app."
  }

  validation {
    condition     = alltrue([for s in var.sidecars : can(regex("^[^\\s:@]+(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}|@sha256:[a-f0-9]{64})$", s.image)) && !endswith(s.image, ":latest")])
    error_message = "Every sidecar image must carry an explicit tag (not latest) or a sha256 digest."
  }

  validation {
    condition     = alltrue([for s in var.sidecars : alltrue([for v in values(s.secrets) : can(regex("^arn:aws[a-z-]*:(secretsmanager|ssm):", v))])])
    error_message = "Every sidecar secret must be a Secrets Manager or SSM parameter ARN."
  }

  validation {
    condition = alltrue([
      for s in var.sidecars : s.app_depends_on == null ? true : (
        contains(["START", "HEALTHY", "COMPLETE", "SUCCESS"], s.app_depends_on)
      )
    ])
    error_message = "app_depends_on must be one of START, HEALTHY, COMPLETE or SUCCESS."
  }

  validation {
    condition     = alltrue([for s in var.sidecars : s.app_depends_on != "HEALTHY" || s.health_check != null])
    error_message = "A sidecar with app_depends_on = HEALTHY must define health_check."
  }

  validation {
    # awsvpc shares one network interface, so ports must be unique across all containers.
    condition = (
      length(distinct(flatten([for s in var.sidecars : [for p in s.port_mappings : p.container_port]]))) == length(flatten([for s in var.sidecars : [for p in s.port_mappings : p.container_port]]))
      && !contains(flatten([for s in var.sidecars : [for p in s.port_mappings : p.container_port]]), coalesce(var.container_port, -1))
    )
    error_message = "Sidecar container_port values must not repeat or collide with the main container_port."
  }
}

variable "enable_execute_command" {
  type        = bool
  default     = false
  description = "Enable ECS Exec. The task role needs the ssmmessages permissions."
}

variable "log_group_name" {
  type        = string
  default     = null
  description = "null uses /ecs/<name>."
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Retention of the service log group."

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts."
  }
}

variable "log_kms_key_arn" {
  type        = string
  default     = null
  description = "KMS key ARN for the log group; null uses the default encryption."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for every resource; Name is added by the module."
}
