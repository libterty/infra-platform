variable "cameras" {
  description = "接 KVS edge connector 的攝影機，key 是攝影機 id（1–32 字元，小寫英數字與 `-`），預設空 map，什麼都不建（design K14）。欄位：`core_thing_name`（接這台攝影機的 core device，名稱是 `<project>-<env>-core-*`）、`rtsp_secret_arn`（RTSP 網址的 Secrets Manager secret ARN，secret 在 repo 外建立）、`retention_hours`（KVS stream 保留時數，1–87600）。`edge` stack 的 `cameras` 要給一模一樣的值。"
  type = map(object({
    core_thing_name = string
    rtsp_secret_arn = string
    retention_hours = number
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for id in keys(var.cameras) : can(regex("^[a-z0-9][a-z0-9-]{0,31}$", id))])
    error_message = "cameras keys must be 1-32 chars of lowercase letters, digits or hyphens."
  }

  validation {
    condition     = alltrue([for c in values(var.cameras) : startswith(c.core_thing_name, "${var.project}-${var.env}-core-") && can(regex("^[a-zA-Z0-9:_-]{1,128}$", c.core_thing_name))])
    error_message = "cameras[*].core_thing_name must be a core device of this project and env (<project>-<env>-core-*), the name the fleet core policy allows."
  }

  validation {
    condition     = alltrue([for c in values(var.cameras) : can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:.+$", c.rtsp_secret_arn))])
    error_message = "cameras[*].rtsp_secret_arn must be a Secrets Manager secret ARN; the RTSP URL itself never goes into tfvars."
  }

  validation {
    condition     = alltrue([for c in values(var.cameras) : c.retention_hours >= 1 && c.retention_hours <= 87600 && floor(c.retention_hours) == c.retention_hours])
    error_message = "cameras[*].retention_hours must be a whole number between 1 and 87600."
  }
}

variable "gateways" {
  description = "跑在 Greengrass v2 core device 上的 SiteWise gateway，key 是名稱（實際名稱是 `<project>-<env>-<key>`），`core_device_thing_name` 是 core device 的 thing 名稱。預設空 map，不建 gateway。"
  type = map(object({
    core_device_thing_name = string
  }))
  default  = {}
  nullable = false
}
