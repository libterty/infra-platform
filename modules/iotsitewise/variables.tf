variable "asset_models" {
  type = map(object({
    description = optional(string)
    properties = optional(map(object({
      data_type     = string
      type          = string
      unit          = optional(string)
      default_value = optional(string)
    })), {})
    hierarchies = optional(map(string), {})
  }))
  default     = {}
  nullable    = false
  description = "SiteWise asset model，key 是名稱（1–256 字元，限英數字、`_`、`-`、`.`）。`properties` 的 key 是 property 名稱，`type` 是 `attribute` 或 `measurement`，`data_type` 是 `STRING`、`INTEGER`、`DOUBLE`、`BOOLEAN`，`unit` 選填，`default_value` 只有 `attribute` 能給；`hierarchies` 是階層名稱對應子 model 的 key（子 model 要在同一個呼叫裡）。階層最多兩層：當子 model 的不能再有自己的 `hierarchies`。每個 model 至少要有一個 property 或階層。"

  validation {
    condition     = alltrue([for name, _ in var.asset_models : can(regex("^[a-zA-Z0-9_.-]{1,256}$", name))])
    error_message = "asset model names must be 1-256 chars of letters, digits, underscores, hyphens or dots."
  }

  validation {
    condition     = alltrue([for _, m in var.asset_models : length(m.properties) + length(m.hierarchies) >= 1])
    error_message = "every asset model must have at least one property or hierarchy."
  }

  validation {
    condition = alltrue(flatten([for _, m in var.asset_models : [
      for name, p in m.properties : can(regex("^[a-zA-Z0-9_.:-]{1,256}$", name)) && contains(["attribute", "measurement"], p.type)
    ]]))
    error_message = "property names must be 1-256 chars of letters, digits, underscores, hyphens, dots or colons, and property type must be attribute or measurement."
  }

  validation {
    condition     = alltrue(flatten([for _, m in var.asset_models : [for _, p in m.properties : contains(["STRING", "INTEGER", "DOUBLE", "BOOLEAN"], p.data_type)]]))
    error_message = "property data_type must be STRING, INTEGER, DOUBLE or BOOLEAN."
  }

  validation {
    condition     = alltrue(flatten([for _, m in var.asset_models : [for _, p in m.properties : p.type == "attribute" || p.default_value == null]]))
    error_message = "default_value is only allowed on attribute properties."
  }

  validation {
    condition = alltrue(flatten([for _, m in var.asset_models : [
      for name, child in m.hierarchies : can(regex("^[a-zA-Z0-9_.:-]{1,256}$", name)) && contains(keys(var.asset_models), child)
    ]]))
    error_message = "hierarchy names must be 1-256 chars of letters, digits, underscores, hyphens, dots or colons, and every hierarchy must point at an asset model key in the same call."
  }

  validation {
    condition = alltrue(flatten([for _, m in var.asset_models : [
      for _, child in m.hierarchies : length(try(var.asset_models[child].hierarchies, {})) == 0
    ]]))
    error_message = "hierarchies support two levels only: a model used as a hierarchy child must not have hierarchies of its own."
  }
}

variable "assets" {
  type = map(object({
    model = string
    parent = optional(object({
      asset     = string
      hierarchy = string
    }))
    properties = optional(map(object({
      alias              = optional(string)
      notification_state = optional(string)
      unit               = optional(string)
    })), {})
  }))
  default     = {}
  nullable    = false
  description = "SiteWise asset，key 是名稱（1–256 字元，限英數字、`_`、`-`、`.`）。`model` 是同一個呼叫裡 `asset_models` 的 key；`parent` 選填，`asset` 是同一個呼叫裡的上層 asset，`hierarchy` 是上層 model 裡指向這個 asset 的 model 的階層名稱（model 階層最多兩層，所以 asset 也最多兩層）；`properties` 的 key 是 model 的 property 名稱，可設 `alias`（例如 gateway 寫入用的資料流別名）、`notification_state`（`ENABLED` 或 `DISABLED`）、`unit`。attribute 的值不能在這裡設，見 README〈注意〉。"

  validation {
    condition     = alltrue([for name, _ in var.assets : can(regex("^[a-zA-Z0-9_.-]{1,256}$", name))])
    error_message = "asset names must be 1-256 chars of letters, digits, underscores, hyphens or dots."
  }

  validation {
    condition     = alltrue([for _, a in var.assets : contains(keys(var.asset_models), a.model)])
    error_message = "every asset model must be an asset_models key in the same call."
  }

  validation {
    condition = alltrue([for _, a in var.assets : a.parent == null || try(
      var.asset_models[var.assets[a.parent.asset].model].hierarchies[a.parent.hierarchy] == a.model
    , false)])
    error_message = "asset parent must be an asset in the same call whose model has the given hierarchy, and that hierarchy must point at this asset's model."
  }

  validation {
    condition = alltrue(flatten([for _, a in var.assets : [
      for name, p in a.properties : contains(keys(try(var.asset_models[a.model].properties, {})), name) && (p.notification_state == null || contains(["ENABLED", "DISABLED"], coalesce(p.notification_state, "-")))
    ]]))
    error_message = "asset properties must be property names of the asset's model, and notification_state must be ENABLED or DISABLED."
  }
}

variable "gateways" {
  type = map(object({
    core_device_thing_name = string
  }))
  default     = {}
  nullable    = false
  description = "跑在 Greengrass v2 core device 上的 SiteWise gateway，key 是 gateway 名稱（1–256 字元，限英數字、`_`、`-`、`.`）。`core_device_thing_name` 是 core device 的 IoT thing 名稱（1–128 字元，限英數字、`:`、`_`、`-`）。"

  validation {
    condition     = alltrue([for name, _ in var.gateways : can(regex("^[a-zA-Z0-9_.-]{1,256}$", name))])
    error_message = "gateway names must be 1-256 chars of letters, digits, underscores, hyphens or dots."
  }

  validation {
    condition     = alltrue([for _, g in var.gateways : can(regex("^[a-zA-Z0-9:_-]{1,128}$", g.core_device_thing_name))])
    error_message = "core_device_thing_name must be an IoT thing name: 1-128 chars of letters, digits, colons, underscores or hyphens."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "所有資源的 tag；module 轉成 awscc 要的 `{ key, value }` 清單，並加上 `Name`（資源名稱）。"
}
