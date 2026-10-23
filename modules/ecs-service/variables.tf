variable "name" {
  type        = string
  description = "service 名稱，2–26 字元，限小寫英數字與連字號，字母開頭；同時是 task family、log group 名稱後綴與 target group 名稱前綴（target group 名稱 `<name>-<container_port>` 上限 32 字元）。"

  validation {
    # Max 26: the target group name is "<name>-<port>" and AWS caps it at 32 chars.
    condition     = can(regex("^[a-z][a-z0-9-]{1,25}$", var.name))
    error_message = "name must be 2-26 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "cluster_arn" {
  type        = string
  description = "ECS cluster 的完整 ARN，來自 `ecs-cluster` module。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:ecs:[a-z0-9-]+:[0-9]{12}:cluster/[A-Za-z0-9_-]+$", var.cluster_arn))
    error_message = "cluster_arn must be a full ECS cluster ARN."
  }
}

variable "image" {
  type        = string
  description = "主 container 的映像，要帶明確 tag（不可 `latest`）或 sha256 digest。"

  validation {
    condition     = can(regex("^[^\\s:@]+(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}|@sha256:[a-f0-9]{64})$", var.image)) && !endswith(var.image, ":latest")
    error_message = "image must carry an explicit tag (not latest) or a sha256 digest."
  }
}

variable "cpu" {
  type        = number
  default     = 512
  description = "task 的 CPU 單位，與 `memory` 要是 Fargate 支援的 Linux 組合（`256`–`4096`）。"
}

variable "memory" {
  type        = number
  default     = 1024
  description = "task 的記憶體（MiB），要與 `cpu` 搭配：`256` 配 `512`／`1024`／`2048`；`512` 配 `1024`–`4096`；`1024` 配 `2048`–`8192`；`2048` 配 `4096`–`16384`；`4096` 配 `8192`–`30720`（範圍皆以 `1024` 為間隔）。"

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
  description = "CPU 架構，`ARM64` 或 `X86_64`，要與映像一致。"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64."
  }
}

variable "container_port" {
  type        = number
  default     = null
  description = "主 container 的 port，1–65535 的整數。設了 `load_balancer` 或 `service_connect` 時必填；沒有 port 的 worker 傳 `null`。"

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
  description = "一般環境變數。"
}

variable "secrets" {
  type        = map(string)
  default     = {}
  description = "環境變數名稱對應 Secrets Manager 或 SSM SecureString 參數 ARN（Secrets Manager 可加 `:json-key::` 後綴），由 execution role 在啟動時讀取。"

  validation {
    condition     = alltrue([for v in values(var.secrets) : can(regex("^arn:aws[a-z-]*:(secretsmanager|ssm):", v))])
    error_message = "Every secret must be a Secrets Manager or SSM parameter ARN."
  }
}

variable "execution_role_arn" {
  type        = string
  description = "task execution role ARN，由呼叫端建立（`iam-base` stack）。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", var.execution_role_arn))
    error_message = "execution_role_arn must be an IAM role ARN."
  }
}

variable "task_role_arn" {
  type        = string
  description = "task role ARN，由呼叫端建立（`iam-app` stack）。"

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
  description = "service 的網路設定，都由呼叫端建立（network stack）。欄位：`subnet_ids`（至少 2 個不同的 subnet，分屬不同 AZ）、`security_group_ids`（至少 1 個）。"

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
  description = "service 的 capacity provider 策略。欄位：`capacity_provider`、`weight`（預設 `1`）、`base`（預設 `0`）。"
}

variable "desired_count" {
  type        = number
  default     = 2
  description = "初始 task 數。之後的變動 service 會忽略，容量由 autoscaling target 管理。"
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
    scheduled_actions = optional(map(object({
      schedule     = string
      timezone     = optional(string, "UTC")
      min_capacity = number
      max_capacity = number
    })), {})
    step_policies = optional(map(object({
      comparison_operator = string
      threshold           = number
      evaluation_periods  = number
      datapoints_to_alarm = optional(number)
      treat_missing_data  = optional(string, "notBreaching")
      cooldown            = optional(number, 300)
      # Exactly one of metric and queries.
      metric = optional(object({
        namespace   = string
        metric_name = string
        dimensions  = optional(map(string), {})
        period      = optional(number, 60)
        statistic   = optional(string, "Average")
      }))
      queries = optional(list(object({
        id          = string
        expression  = optional(string)
        label       = optional(string)
        return_data = optional(bool)
        metric = optional(object({
          namespace   = string
          metric_name = string
          dimensions  = optional(map(string), {})
          period      = optional(number, 60)
          stat        = optional(string, "Average")
        }))
      })))
      adjustments = list(object({
        lower  = optional(number)
        upper  = optional(number)
        change = number
      }))
    })), {})
  })
  default     = null
  description = "autoscaling 設定；`null` 時仍建 scalable target，`min = max = desired_count`。`policy` 可為 `target_tracking`（預設）、`step`、`custom`，`custom` 不建內建 policy；`scheduled_actions`、`step_policies`（皆預設 `{}`）可搭配任何 policy。行為見〈Autoscaling〉，欄位見〈`autoscaling` 欄位〉。"

  validation {
    condition = var.autoscaling == null ? true : (
      contains(["target_tracking", "step", "custom"], var.autoscaling.policy) &&
      var.autoscaling.min_capacity >= 1 &&
      var.autoscaling.max_capacity >= var.autoscaling.min_capacity
    )
    error_message = "policy must be target_tracking, step or custom, and 1 <= min_capacity <= max_capacity."
  }

  validation {
    condition = var.autoscaling == null ? true : alltrue([
      for k, p in var.autoscaling.step_policies :
      can(regex("^[a-z][a-z0-9_]*$", k)) && (p.metric == null) != (p.queries == null)
    ])
    error_message = "step_policies keys must be snake_case, and each entry needs exactly one of metric and queries."
  }

  validation {
    condition = var.autoscaling == null ? true : alltrue([
      for k, a in var.autoscaling.scheduled_actions :
      can(regex("^[a-z][a-z0-9_]*$", k)) &&
      a.min_capacity <= a.max_capacity &&
      a.max_capacity <= var.autoscaling.max_capacity
    ])
    error_message = "scheduled_actions keys must be snake_case, min_capacity must not exceed max_capacity, and max_capacity must not exceed autoscaling.max_capacity."
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

variable "system_controls" {
  type        = map(string)
  default     = {}
  description = "`app` container 的 namespaced 核心參數，例如 `net.ipv4.tcp_keepalive_time` 對應 `\"240\"`。空的時候 container definition 不含 `systemControls`；非空會產生新的 task definition 並觸發一次部署。見〈system_controls〉。"
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
  description = "LB 設定；`null` 時不接 LB。`target_group_arn`（外部 target group）與 `listener_arn`（module 建 target group 與 listener rule）擇一。接法見〈兩種 LB 接法〉，欄位見〈`load_balancer` 欄位〉。"

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
  description = "health check 寬限秒數，只在設了 `load_balancer` 時套用，否則 service 拿到 `null`。"
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
  description = "主 container 的 health check；`null` 時不設。欄位：`command`（必填）、`interval`（預設 `10`）、`timeout`（預設 `5`）、`retries`（預設 `3`）、`start_period`（預設 `60`）。"
}

variable "service_connect" {
  type = object({
    namespace_arn = string
    dns_name      = optional(string) # null uses var.name
  })
  default     = null
  description = "Service Connect 註冊；`null` 時停用。欄位：`namespace_arn`（必填）、`dns_name`（`null` 時用 `name`）。"
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
  description = "主 container `app` 以外的 container；空 list 時 task definition 與單一 container 時完全一致。行為見〈Sidecars〉，欄位見〈`sidecars` 欄位〉。"

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
  description = "啟用 ECS Exec。task role 需要 `ssmmessages` 權限。"
}

variable "log_group_name" {
  type        = string
  default     = null
  description = "service 的 log group 名稱；`null` 時用 `/ecs/<name>`。"
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "service log group 的保留天數，必須是 CloudWatch Logs 接受的值（例如 `1`、`7`、`30`、`365`）。"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts."
  }
}

variable "log_kms_key_arn" {
  type        = string
  default     = null
  description = "log group 的 KMS key ARN；`null` 時用預設加密。"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "每個資源的 tag；`Name` 由 module 加上。"
}
