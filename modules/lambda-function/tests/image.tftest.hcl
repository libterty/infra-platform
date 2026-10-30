mock_provider "aws" {}

variables {
  name      = "alpha-dev-worker"
  image_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker:v1.0.0"
  role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-worker"
}

run "rejects_image_uri_from_docker_hub" {
  command = plan

  variables {
    image_uri = "nginx:1.27"
  }

  expect_failures = [var.image_uri]
}

run "rejects_image_uri_from_ecr_public" {
  command = plan

  variables {
    image_uri = "public.ecr.aws/alpha/worker:v1"
  }

  expect_failures = [var.image_uri]
}

run "rejects_image_uri_without_tag_or_digest" {
  command = plan

  variables {
    image_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker"
  }

  expect_failures = [var.image_uri]
}

run "rejects_image_uri_with_latest_tag" {
  command = plan

  variables {
    image_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker:latest"
  }

  expect_failures = [var.image_uri]
}

run "rejects_image_uri_with_uppercase_latest_tag" {
  command = plan

  variables {
    image_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker:LATEST"
  }

  expect_failures = [var.image_uri]
}

run "rejects_image_uri_with_short_digest" {
  command = plan

  variables {
    image_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker@sha256:abc123"
  }

  expect_failures = [var.image_uri]
}

run "rejects_image_uri_with_scheme" {
  command = plan

  variables {
    image_uri = "https://111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker:v1"
  }

  expect_failures = [var.image_uri]
}

run "accepts_image_uri_with_tag" {
  command = plan

  variables {
    image_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker:v2.3.4"
  }

  assert {
    condition     = aws_lambda_function.this[0].image_uri == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker:v2.3.4"
    error_message = "An ECR URI with a version tag must be accepted"
  }
}

run "accepts_image_uri_with_digest" {
  command = plan

  variables {
    image_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  }

  assert {
    condition     = aws_lambda_function.this[0].image_uri == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    error_message = "An ECR URI with a sha256 digest must be accepted"
  }
}

run "accepts_image_uri_with_tag_that_starts_with_latest" {
  command = plan

  variables {
    image_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker:latest-1"
  }

  assert {
    condition     = aws_lambda_function.this[0].image_uri == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker:latest-1"
    error_message = "Only the exact latest tag is rejected"
  }
}
