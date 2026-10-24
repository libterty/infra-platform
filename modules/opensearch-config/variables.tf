variable "ism_policies" {
  type = map(object({
    index_patterns  = list(string)
    warm_days       = optional(number)
    cold_days       = optional(number)
    delete_days     = number
    timestamp_field = optional(string)
  }))
  default     = {}
  nullable    = false
  description = "ISM policy，key 是 policy id。`index_patterns` 是新 index 自動套用這份 policy 的樣式；`warm_days`、`cold_days`、`delete_days` 是 index 年齡（天，從建立算起、累計）：到 `warm_days` 搬進 UltraWarm、到 `cold_days` 搬進 cold、到 `delete_days` 刪除，三個要嚴格遞增。沒給 `warm_days` 就沒有 warm 階段（hot 直接到刪除）。有 `cold_days` 就必須有 `warm_days` 與 `timestamp_field`（搬到 cold 一定要指定時間欄位）。"

  validation {
    condition = alltrue([
      for id, p in var.ism_policies :
      can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$", id)) && length(p.index_patterns) > 0 && alltrue([for x in p.index_patterns : length(x) > 0])
    ])
    error_message = "ism_policies keys must be 1-128 chars of letters, digits, underscores, hyphens or dots, and every policy needs at least one non-empty index pattern."
  }

  validation {
    condition = alltrue([
      for p in values(var.ism_policies) :
      p.delete_days >= 1 && p.delete_days == floor(p.delete_days) &&
      (p.warm_days == null ? true : (p.warm_days >= 1 && p.warm_days == floor(p.warm_days) && p.warm_days < coalesce(p.cold_days, p.delete_days))) &&
      (p.cold_days == null ? true : (p.cold_days == floor(p.cold_days) && p.cold_days < p.delete_days))
    ])
    error_message = "ism_policies days must be whole numbers and strictly increase: warm_days < cold_days < delete_days (delete_days is at least 1)."
  }

  validation {
    condition = alltrue([
      for p in values(var.ism_policies) :
      p.cold_days == null ? true : (p.warm_days != null && try(length(p.timestamp_field) > 0, false))
    ])
    error_message = "ism_policies with cold_days need warm_days and a timestamp_field: ISM cannot move an index to cold storage without one."
  }
}

variable "writer_roles" {
  type = map(object({
    index_patterns    = list(string)
    backend_role_arns = list(string)
  }))
  default     = {}
  nullable    = false
  description = "寫入用的 FGAC role，key 是 role 名稱。權限固定是 AWS 文件給 Firehose 的那組：cluster `cluster_composite_ops`、`cluster_monitor`；對 `index_patterns` 的 index 有 `create_index`、`manage`、`crud`。`backend_role_arns` 是對應的 IAM role ARN（例如 Firehose 的 role），至少一個。`index_patterns` 不能只有 `*`，要限定 index 前綴。"

  validation {
    condition     = alltrue([for name in keys(var.writer_roles) : can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$", name)) && !contains(["all_access", "security_manager"], name)])
    error_message = "writer_roles names must be 1-128 chars of letters, digits, underscores, hyphens or dots, and must not be all_access or security_manager."
  }

  validation {
    condition = alltrue([
      for r in values(var.writer_roles) :
      length(r.index_patterns) > 0 && alltrue([for x in r.index_patterns : length(x) > 0 && x != "*"])
    ])
    error_message = "writer_roles index_patterns must not be empty and must not be a bare * (limit the role to an index prefix)."
  }

  validation {
    condition = alltrue([
      for r in values(var.writer_roles) :
      length(r.backend_role_arns) > 0 && alltrue([for a in r.backend_role_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", a))])
    ])
    error_message = "writer_roles backend_role_arns must hold at least one IAM role ARN (arn:<partition>:iam::<account>:role/<name>) without wildcards."
  }
}

variable "role_mappings" {
  type = map(object({
    users             = optional(list(string), [])
    backend_role_arns = optional(list(string), [])
  }))
  default     = {}
  nullable    = false
  description = "內建 role 的 mapping，key 是 role 名稱，例如 `ultrawarm_manager`、`cold_manager`。`users` 是 internal user 名稱，`backend_role_arns` 是 IAM role ARN，至少給一種。這個資源會取代 role 現有的整份 mapping。不准 mapping `all_access`、`security_manager`，也不能跟 `writer_roles` 的名稱重複。"

  validation {
    condition     = alltrue([for name in keys(var.role_mappings) : !contains(["all_access", "security_manager"], name)])
    error_message = "role_mappings must not map all_access or security_manager: those roles stay with the master user."
  }

  validation {
    condition     = alltrue([for m in values(var.role_mappings) : length(m.users) + length(m.backend_role_arns) > 0])
    error_message = "every role_mappings entry needs at least one user or backend role ARN."
  }

  validation {
    condition = alltrue([
      for m in values(var.role_mappings) :
      alltrue([for a in m.backend_role_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", a))])
    ])
    error_message = "role_mappings backend_role_arns must be IAM role ARNs (arn:<partition>:iam::<account>:role/<name>) without wildcards."
  }

  validation {
    condition     = length(setintersection(toset(keys(var.role_mappings)), toset(keys(var.writer_roles)))) == 0
    error_message = "role_mappings must not reuse a writer_roles name: the writer role already manages its own mapping."
  }
}

variable "index_templates" {
  type = map(object({
    index_patterns     = list(string)
    priority           = optional(number, 100)
    number_of_shards   = optional(number)
    number_of_replicas = optional(number)
    mappings           = optional(string)
  }))
  default     = {}
  nullable    = false
  description = "composable index template，key 是 template 名稱。`mappings` 是 JSON 字串（例如把 ISM 要用的 `timestamp_field` 定義成 `date`），不給就不設 mappings。`priority` 預設 100。"

  validation {
    condition = alltrue([
      for name, t in var.index_templates :
      can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$", name)) && length(t.index_patterns) > 0 && alltrue([for x in t.index_patterns : length(x) > 0])
    ])
    error_message = "index_templates keys must be 1-128 chars of letters, digits, underscores, hyphens or dots, and every template needs at least one non-empty index pattern."
  }

  validation {
    condition     = alltrue([for t in values(var.index_templates) : t.priority >= 0 && t.priority == floor(t.priority)])
    error_message = "index_templates priority must be a whole number of 0 or more."
  }

  validation {
    condition     = alltrue([for t in values(var.index_templates) : t.mappings == null ? true : can(jsondecode(t.mappings))])
    error_message = "index_templates mappings must be a valid JSON string."
  }
}
