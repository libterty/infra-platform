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

module "worker" {
  source = "../.."

  name      = "alpha-dev-worker"
  image_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker:v1.0.0"
  role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-worker"

  memory_size = 1024
  timeout     = 60

  environment = {
    LOG_LEVEL     = "info"
    DB_SECRET_ARN = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-db-AbCdEf"
    UPLOAD_BUCKET = "alpha-dev-uploads"
  }

  vpc = {
    subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
    security_group_ids = ["sg-0123456789abcdef0"]
  }

  log_format = "JSON"

  permissions = {
    s3_upload = {
      principal      = "s3.amazonaws.com"
      source_arn     = "arn:aws:s3:::alpha-dev-uploads"
      source_account = "111111111111"
    }
  }

  tags = {
    Project = "alpha"
  }
}

# Use function_arn (not a hand-built ARN) so the notification waits for the permission.
resource "aws_s3_bucket_notification" "uploads" {
  bucket = "alpha-dev-uploads"

  lambda_function {
    lambda_function_arn = module.worker.function_arn
    events              = ["s3:ObjectCreated:*"]
  }
}

output "function_name" {
  value = module.worker.function_name
}
