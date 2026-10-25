variable "vpc_cidr" {
  description = "VPC 的 IPv4 網路位址，`/16` 到 `/24`（例如 `10.40.0.0/20`）。app 與 data 兩個 tier 從這段切出來。"
  type        = string
}

variable "azs" {
  description = "VPC 使用的 AZ，用 2 個。順序決定 SSM 發布的 list 的順序。"
  type        = list(string)
}

variable "flow_log" {
  description = "是否把 VPC flow log 送到 `foundation` 的 flow log bucket。"
  type        = bool
  default     = true
}

variable "interface_endpoint_services" {
  description = "要建的 interface endpoint，只接受 `sagemaker.runtime`；預設空清單，不建任何 endpoint。`inference` 有 endpoint、而且要從 VPC 內呼叫時才加。只有 VPC 的網段能連 endpoint 的 443 port。"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.interface_endpoint_services : s == "sagemaker.runtime"])
    error_message = "interface_endpoint_services accepts only sagemaker.runtime (design K33)."
  }
}
