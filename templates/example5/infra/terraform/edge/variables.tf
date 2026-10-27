variable "deployments" {
  description = "Greengrass 部署，key 是名稱（實際名稱是 `<project>-<env>-<key>`），每個 thing group 最多一個。欄位：`thing_group`（`fleet` 或 `core`）、`components`（元件名稱對應版本；一定要有 `aws.greengrass.Nucleus`，自訂元件的版本要有 recipe 檔）、`rollout`（`maximum_per_minute`，1–1000）、`abort`（`threshold_percentage` 失敗比例，大於 0、最多 100；`min_number_of_executed_things` 至少執行幾台才判斷，預設 10）。部署失敗一律 rollback。"
  type = map(object({
    thing_group = string
    components  = map(string)
    rollout = object({
      maximum_per_minute = number
    })
    abort = object({
      threshold_percentage          = number
      min_number_of_executed_things = optional(number, 10)
    })
  }))

  validation {
    condition     = length(var.deployments) >= 1 && alltrue([for k in keys(var.deployments) : can(regex("^[a-z0-9][a-z0-9-]{0,31}$", k))])
    error_message = "deployments needs at least one entry; keys must be 1-32 chars of lowercase letters, digits or hyphens."
  }

  validation {
    condition     = alltrue([for d in values(var.deployments) : contains(["fleet", "core"], d.thing_group)])
    error_message = "deployments[*].thing_group must be fleet or core; unverified and quarantine devices never receive deployments."
  }

  validation {
    condition     = length(distinct([for d in values(var.deployments) : d.thing_group])) == length(var.deployments)
    error_message = "A thing group has one deployment only: a second deployment to the same group replaces the first."
  }

  validation {
    condition     = alltrue([for d in values(var.deployments) : contains(keys(d.components), "aws.greengrass.Nucleus")])
    error_message = "Every deployment must pin aws.greengrass.Nucleus (design K12)."
  }
}

variable "camera_deployment" {
  description = "`cameras` 不空時，每台 core device 一個 thing 層級部署用的元件版本：`nucleus_version`（要跟群組部署的 Nucleus 一樣）、`stream_manager_version`、`edge_connector_version`（`aws.iot.EdgeConnectorForKVS`）。"
  type = object({
    nucleus_version        = string
    stream_manager_version = string
    edge_connector_version = string
  })
}

variable "cameras" {
  description = "接 KVS edge connector 的攝影機，key 是攝影機 id（1–32 字元，小寫英數字與 `-`），預設空 map，什麼都不建（design K14）。欄位：`core_thing_name`（接這台攝影機的 core device，名稱是 `<project>-<env>-core-*`）、`rtsp_secret_arn`（RTSP 網址的 Secrets Manager secret ARN，secret 在 repo 外建立，名稱必須是 `<project>-<env>/cameras/<攝影機 id>`，值是 key 為 `RTSPStreamUrl` 的 JSON）、`retention_hours`（KVS stream 保留時數，1–87600）。`sitewise` stack 的 `cameras` 要給一模一樣的值。"
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

  # Naming rule of iam-base (naming.tf): the greengrass-tes role may read only secrets named <project>-<env>/cameras/*.
  # A secret ARN ends in -<6 random characters>.
  validation {
    condition = alltrue([for id, c in var.cameras : can(regex(
      "^arn:aws:secretsmanager:${var.aws_region}:${var.expected_account_id}:secret:${var.project}-${var.env}/cameras/${id}-[A-Za-z0-9]{6}$", c.rtsp_secret_arn
    ))])
    error_message = "cameras[*].rtsp_secret_arn must be the secret <project>-<env>/cameras/<camera id> in this account and region: the greengrass-tes role of iam-base reads only those."
  }

  validation {
    condition     = alltrue([for c in values(var.cameras) : c.retention_hours >= 1 && c.retention_hours <= 87600 && floor(c.retention_hours) == c.retention_hours])
    error_message = "cameras[*].retention_hours must be a whole number between 1 and 87600."
  }
}
