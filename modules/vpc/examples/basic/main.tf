terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

module "vpc" {
  source = "../.."

  name = "alpha-dev"
  cidr = "10.20.0.0/20"
  azs  = ["ap-northeast-1a", "ap-northeast-1c"]

  # 每個 tier 預留 4 個 AZ 的槽位，之後加到 3、4 個 AZ 時既有 subnet 不用動。
  subnets = {
    public = { type = "public", newbits = 4, netnum_base = 0 }
    app    = { type = "private", newbits = 4, netnum_base = 4 }
    data   = { type = "isolated", newbits = 4, netnum_base = 8 }
  }

  nat_mode = "single"

  tags = {
    Project = "alpha"
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "subnet_ids" {
  value = module.vpc.subnet_ids
}
