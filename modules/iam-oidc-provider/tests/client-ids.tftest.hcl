mock_provider "aws" {}

variables {
  issuer_url = "https://oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
}

run "default_is_sts" {
  command = plan

  assert {
    condition     = aws_iam_openid_connect_provider.this.client_id_list == toset(["sts.amazonaws.com"])
    error_message = "client_ids must default to sts.amazonaws.com"
  }
}

run "custom_client_ids" {
  command = plan

  variables {
    client_ids = ["sts.amazonaws.com", "other.example"]
  }

  assert {
    condition     = aws_iam_openid_connect_provider.this.client_id_list == toset(["sts.amazonaws.com", "other.example"])
    error_message = "custom client_ids must be passed through"
  }
}

run "empty_client_ids_rejected" {
  command = plan

  variables {
    client_ids = []
  }

  expect_failures = [var.client_ids]
}

run "blank_client_id_rejected" {
  command = plan

  variables {
    client_ids = [""]
  }

  expect_failures = [var.client_ids]
}

run "client_id_with_space_rejected" {
  command = plan

  variables {
    client_ids = ["sts amazonaws.com"]
  }

  expect_failures = [var.client_ids]
}

run "client_id_too_long_rejected" {
  command = plan

  variables {
    client_ids = [join("", [for i in range(256) : "a"])]
  }

  expect_failures = [var.client_ids]
}
