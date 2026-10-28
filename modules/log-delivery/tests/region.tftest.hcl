mock_provider "aws" {
  mock_resource "aws_cloudwatch_log_delivery_destination" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:111111111111:delivery-destination:mock"
    }
  }
}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

variables {
  name_prefix = "alpha-dev"

  sources = {
    cdn = {
      resource_arn = "arn:aws:cloudfront::111111111111:distribution/E1ABCDEFGHIJKL"
      log_type     = "ACCESS_LOGS"
    }
  }

  destinations = {
    cdn-logs = {
      type         = "S3"
      resource_arn = "arn:aws:s3:::alpha-dev-cdn-logs"
    }
  }

  deliveries = {
    cdn = {
      source      = "cdn"
      destination = "cdn-logs"
    }
  }
}

run "region_defaults_to_null" {
  command = plan

  assert {
    condition     = var.region == null
    error_message = "region must default to null so resources follow the provider region"
  }
}

run "region_applies_to_source_destination_and_delivery" {
  command = plan

  variables {
    region = "us-east-1"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this["cdn"].region == "us-east-1"
    error_message = "The delivery source must be created in region"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.this["cdn-logs"].region == "us-east-1"
    error_message = "The delivery destination must be created in region"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.this["cdn"].region == "us-east-1"
    error_message = "The delivery must be created in region"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this["cdn"].resource_arn == "arn:aws:cloudfront::111111111111:distribution/E1ABCDEFGHIJKL" && aws_cloudwatch_log_delivery_source.this["cdn"].log_type == "ACCESS_LOGS"
    error_message = "A CloudFront distribution must be accepted as a source"
  }
}

run "region_with_uppercase_is_rejected" {
  command = plan

  variables {
    region = "US-EAST-1"
  }

  expect_failures = [var.region]
}

run "region_without_number_is_rejected" {
  command = plan

  variables {
    region = "us-east"
  }

  expect_failures = [var.region]
}

run "empty_region_is_rejected" {
  command = plan

  variables {
    region = ""
  }

  expect_failures = [var.region]
}
