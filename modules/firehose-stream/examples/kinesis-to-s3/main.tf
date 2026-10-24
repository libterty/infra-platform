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

module "raw" {
  source = "../.."

  name              = "alpha-dev-raw"
  role_arn          = "arn:aws:iam::111111111111:role/alpha-dev-firehose"
  kms_key_arn       = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  source_stream_arn = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/alpha-dev-events"

  s3 = {
    bucket_arn          = "arn:aws:s3:::alpha-dev-raw"
    prefix              = "raw/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
  }

  tags = {
    Project = "alpha"
  }
}

# The same module delivers to a VPC OpenSearch domain; the S3 input then only keeps failed documents.
module "search" {
  source = "../.."

  name              = "alpha-dev-search"
  role_arn          = "arn:aws:iam::111111111111:role/alpha-dev-firehose"
  kms_key_arn       = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  source_stream_arn = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/alpha-dev-events"

  s3 = {
    bucket_arn = "arn:aws:s3:::alpha-dev-raw"
    prefix     = "errors/"
  }

  opensearch = {
    domain_arn         = "arn:aws:es:ap-northeast-1:111111111111:domain/alpha-dev-search"
    index_name         = "alpha-dev-events"
    subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    security_group_ids = ["sg-0123456789abcdef0"]
  }

  tags = {
    Project = "alpha"
  }
}

output "raw_stream_arn" {
  value = module.raw.arn
}

output "search_stream_arn" {
  value = module.search.arn
}
