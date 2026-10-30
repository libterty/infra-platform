variable "vpc_cidr" {
  description = "VPC 的 CIDR，必須是 `/16` 的網路位址；vpc.tf 的 subnet 切法依它計算。"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && can(regex("/16$", var.vpc_cidr)) && cidrsubnet(var.vpc_cidr, 0, 0) == var.vpc_cidr
    error_message = "vpc_cidr must be an IPv4 /16 network address such as 10.30.0.0/16."
  }
}

variable "azs" {
  description = "AZ 清單，順序固定；每個 tier 在每個 AZ 各一個 subnet。"
  type        = list(string)

  validation {
    # The layout reserves three slots per tier.
    condition     = length(var.azs) >= 2 && length(var.azs) <= 3 && length(distinct(var.azs)) == length(var.azs)
    error_message = "azs must list 2 or 3 distinct availability zones."
  }
}

variable "nat_mode" {
  description = "`single` 在第一個 AZ 建一個 NAT（那個 AZ 故障時 app subnet 連不到外面）；`per_az` 每個 AZ 一個。ECS task 要經 NAT 拉 ECR 映像檔、寫 log，所以不提供 `none`。"
  type        = string
  default     = "single"

  validation {
    condition     = contains(["single", "per_az"], var.nat_mode)
    error_message = "nat_mode must be single or per_az; the app tier needs a NAT to reach ECR and CloudWatch Logs."
  }
}
