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

locals {
  # Minimal collector config: OTLP in, X-Ray out. Passed through environment, not a secret.
  collector_config = <<-YAML
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
    processors:
      batch: {}
    exporters:
      awsxray: {}
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [awsxray]
  YAML
}

# ARNs and IDs are placeholders for values a real stack reads from SSM.
# The task role needs the X-Ray write permissions; the execution role must be able to pull the collector image.
module "api" {
  source = "../.."

  name           = "alpha-api"
  cluster_arn    = "arn:aws:ecs:ap-northeast-1:111111111111:cluster/alpha-dev"
  image          = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-api:1.0.0"
  container_port = 8080

  execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-ecs-execution"
  task_role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-alpha-api-task"

  network = {
    subnet_ids         = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
    security_group_ids = ["sg-0cccccccccccccccc"]
  }

  # Containers share the task network interface, so localhost reaches the collector.
  environment = { OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4317" }

  sidecars = [{
    name               = "adot-collector"
    image              = "public.ecr.aws/aws-observability/aws-otel-collector:v0.43.1"
    essential          = false
    cpu                = 128
    memory_reservation = 256
    environment        = { AOT_CONFIG_CONTENT = local.collector_config }
    port_mappings      = [{ container_port = 4317 }]
    health_check       = { command = ["CMD", "/healthcheck"] }
    app_depends_on     = "START"
  }]

  tags = { Project = "alpha" }
}

output "service_name" {
  value = module.api.service_name
}
