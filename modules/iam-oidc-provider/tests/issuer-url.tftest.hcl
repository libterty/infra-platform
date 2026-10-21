mock_provider "aws" {}

variables {
  issuer_url = "https://oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
}

run "eks_issuer_accepted" {
  command = plan

  assert {
    condition     = aws_iam_openid_connect_provider.this.url == "https://oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
    error_message = "url must be passed through unchanged"
  }
}

run "other_region_accepted" {
  command = plan

  variables {
    issuer_url = "https://oidc.eks.us-east-1.amazonaws.com/id/0123456789abcdef"
  }

  assert {
    condition     = aws_iam_openid_connect_provider.this.url == "https://oidc.eks.us-east-1.amazonaws.com/id/0123456789abcdef"
    error_message = "any region host must be accepted"
  }
}

run "http_scheme_rejected" {
  command = plan

  variables {
    issuer_url = "http://oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
  }

  expect_failures = [var.issuer_url]
}

run "trailing_slash_rejected" {
  command = plan

  variables {
    issuer_url = "https://oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE/"
  }

  expect_failures = [var.issuer_url]
}

run "missing_id_rejected" {
  command = plan

  variables {
    issuer_url = "https://oidc.eks.ap-northeast-1.amazonaws.com/id/"
  }

  expect_failures = [var.issuer_url]
}

run "extra_path_rejected" {
  command = plan

  variables {
    issuer_url = "https://oidc.eks.ap-northeast-1.amazonaws.com/id/ABC/extra"
  }

  expect_failures = [var.issuer_url]
}

run "lookalike_host_rejected" {
  command = plan

  variables {
    issuer_url = "https://oidc.eks.ap-northeast-1.amazonaws.com.evil.example/id/ABC"
  }

  expect_failures = [var.issuer_url]
}

run "non_eks_issuer_rejected" {
  command = plan

  variables {
    issuer_url = "https://token.actions.githubusercontent.com"
  }

  expect_failures = [var.issuer_url]
}

run "uppercase_region_rejected" {
  command = plan

  variables {
    issuer_url = "https://oidc.eks.AP-NORTHEAST-1.amazonaws.com/id/ABC"
  }

  expect_failures = [var.issuer_url]
}

run "whitespace_rejected" {
  command = plan

  variables {
    issuer_url = "https://oidc.eks.ap-northeast-1.amazonaws.com/id/ABC DEF"
  }

  expect_failures = [var.issuer_url]
}

run "empty_rejected" {
  command = plan

  variables {
    issuer_url = ""
  }

  expect_failures = [var.issuer_url]
}
