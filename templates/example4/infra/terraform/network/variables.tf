variable "vpc_cidr" {
  description = "VPC 的 IPv4 網路位址，`/16` 到 `/24`（例如 `10.30.0.0/20`）。app 與 data 兩個 tier 從這段切出來。"
  type        = string
}

variable "azs" {
  description = "VPC 使用的 AZ，資料平台用 2 個。順序決定 SSM 發布的 list 的順序。"
  type        = list(string)
}

variable "flow_log" {
  description = "是否把 VPC flow log 送到 `foundation` 的 flow log bucket。"
  type        = bool
  default     = true
}
