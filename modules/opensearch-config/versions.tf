terraform {
  required_version = ">= 1.10"

  required_providers {
    opensearch = {
      source  = "opensearch-project/opensearch"
      version = ">= 2.6.0, < 3.0"
    }
  }
}
