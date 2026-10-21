terraform {
  required_version = ">= 1.10"

  required_providers {
    helm = {
      source = "hashicorp/helm"
      # 3.x moved set to a list of objects; the module is written against that schema.
      version = ">= 3.0, < 4.0"
    }
  }
}
