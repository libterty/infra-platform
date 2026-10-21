terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.69 is the version whose schema this module was written against (deletion_protection, zonal_shift_config, Auto Mode blocks).
      version = ">= 6.69, < 7.0"
    }
  }
}
