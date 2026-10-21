mock_provider "aws" {}

variables {
  issuer_url = "https://oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
}

run "issuer_drops_scheme" {
  command = plan

  assert {
    condition     = output.issuer == "oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
    error_message = "issuer must be the URL without https://"
  }
}

run "arn_comes_from_resource" {
  command = apply

  override_resource {
    target = aws_iam_openid_connect_provider.this
    values = {
      arn = "arn:aws:iam::111111111111:oidc-provider/oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
    }
  }

  assert {
    condition     = output.arn == "arn:aws:iam::111111111111:oidc-provider/oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
    error_message = "arn must be the provider ARN"
  }
}

run "tags_applied" {
  command = plan

  variables {
    tags = { Project = "alpha", Env = "dev" }
  }

  assert {
    condition     = aws_iam_openid_connect_provider.this.tags == tomap({ Project = "alpha", Env = "dev" })
    error_message = "tags must be passed through"
  }
}

run "thumbprint_list_not_set" {
  command = plan

  assert {
    condition     = length(regexall("thumbprint_list", file("${path.module}/main.tf"))) == 0
    error_message = "main.tf must not set thumbprint_list; AWS verifies EKS issuers with its trusted root CAs"
  }
}
