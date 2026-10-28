variable "zone_id" {
  type        = string
  description = "record 所在的 hosted zone ID（`route53-zone` 的 `zone_id` 輸出），例如 `Z0123456789ABCDEFGHIJ`。"

  validation {
    condition     = can(regex("^Z[A-Z0-9]{1,31}$", var.zone_id))
    error_message = "zone_id must be a hosted zone ID such as Z0123456789ABCDEFGHIJ."
  }
}

variable "records" {
  type = map(object({
    name   = string
    type   = string
    ttl    = optional(number)
    values = optional(list(string))
    alias = optional(object({
      name                   = string
      zone_id                = string
      evaluate_target_health = optional(bool, false)
    }))
  }))
  nullable    = false
  description = "這個 zone 裡要建的 record，key 是短名（只用在 Terraform address 與 `fqdns` 輸出）。欄位：`name`（record 名稱，例如 `app.dev.example.com`）、`type`（`A`、`AAAA`、`CNAME`、`TXT`、`MX`、`NS`、`CAA`、`SRV`）。其餘二選一：一般 record 給 `values`（非空）與 `ttl`（60–172800 秒），`CNAME` 只能一個值；alias 給 `alias = { name, zone_id, evaluate_target_health }`（`evaluate_target_health` 預設 `false`），只能用在 `A`、`AAAA`，不給 `ttl`。"

  validation {
    condition     = alltrue([for r in values(var.records) : contains(["A", "AAAA", "CNAME", "TXT", "MX", "NS", "CAA", "SRV"], r.type)])
    error_message = "records type must be A, AAAA, CNAME, TXT, MX, NS, CAA or SRV."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : (r.alias != null) != (length(coalesce(r.values, [])) > 0)])
    error_message = "Each record needs either non-empty values or alias, not both."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : r.alias == null || contains(["A", "AAAA"], r.type)])
    error_message = "records alias is only allowed for type A or AAAA."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : r.alias != null || (r.ttl != null && try(r.ttl >= 60 && r.ttl <= 172800 && r.ttl == floor(r.ttl), false))])
    error_message = "records without alias need ttl, a whole number between 60 and 172800 seconds."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : r.alias == null || r.ttl == null])
    error_message = "records with alias must not set ttl; Route 53 uses the alias target TTL."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : r.type != "CNAME" || length(coalesce(r.values, [])) <= 1])
    error_message = "A CNAME record must have exactly one value."
  }
}
