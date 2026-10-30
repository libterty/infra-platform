mock_provider "aws" {}

variables {
  name = "alpha-dev-github"
}

# ---- positive -------------------------------------------------------------------------------------------------

run "defaults_to_github" {
  command = plan

  assert {
    condition     = aws_codeconnections_connection.this.name == "alpha-dev-github"
    error_message = "The connection must keep the given name"
  }

  assert {
    condition     = aws_codeconnections_connection.this.provider_type == "GitHub"
    error_message = "provider_type must default to GitHub"
  }

  assert {
    condition     = aws_codeconnections_connection.this.host_arn == null
    error_message = "A cloud provider must not set host_arn"
  }

  assert {
    condition     = aws_codeconnections_connection.this.tags == tomap({ Name = "alpha-dev-github" })
    error_message = "Without tags input the only tag is Name"
  }
}

run "gitlab_self_managed_with_host" {
  command = plan

  variables {
    name          = "alpha-dev-gitlab"
    provider_type = "GitLabSelfManaged"
    host_arn      = "arn:aws:codeconnections:ap-northeast-1:111111111111:host/alpha-gitlab-0123abcd"
  }

  assert {
    condition     = aws_codeconnections_connection.this.host_arn == "arn:aws:codeconnections:ap-northeast-1:111111111111:host/alpha-gitlab-0123abcd"
    error_message = "host_arn must follow the input"
  }
}

run "accepts_codestar_connections_host_arn" {
  command = plan

  variables {
    provider_type = "GitHubEnterpriseServer"
    host_arn      = "arn:aws:codestar-connections:ap-northeast-1:111111111111:host/alpha-ghes-0123abcd"
  }

  assert {
    condition     = aws_codeconnections_connection.this.host_arn == "arn:aws:codestar-connections:ap-northeast-1:111111111111:host/alpha-ghes-0123abcd"
    error_message = "A host ARN in the old codestar-connections namespace must be accepted"
  }
}

run "other_cloud_providers" {
  command = plan

  variables {
    provider_type = "Bitbucket"
  }

  assert {
    condition     = aws_codeconnections_connection.this.provider_type == "Bitbucket"
    error_message = "provider_type must follow the input"
  }
}

run "accepts_name_of_32_chars" {
  command = plan

  variables {
    name = "a${join("", [for i in range(31) : "b"])}"
  }

  assert {
    condition     = length(aws_codeconnections_connection.this.name) == 32
    error_message = "A 32-char name must be accepted"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_codeconnections_connection.this.tags == tomap({ Project = "alpha", Name = "alpha-dev-github" })
    error_message = "Input tags must be kept and Name added"
  }
}

run "region_follows_input" {
  command = plan

  variables {
    region = "us-east-1"
  }

  assert {
    condition     = aws_codeconnections_connection.this.region == "us-east-1"
    error_message = "region must be set on the connection"
  }
}

run "outputs" {
  command = apply

  override_resource {
    target = aws_codeconnections_connection.this
    values = {
      arn               = "arn:aws:codeconnections:ap-northeast-1:111111111111:connection/0a1b2c3d-0a1b-0a1b-0a1b-0a1b2c3d4e5f"
      connection_status = "PENDING"
    }
  }

  assert {
    condition     = output.arn == "arn:aws:codeconnections:ap-northeast-1:111111111111:connection/0a1b2c3d-0a1b-0a1b-0a1b-0a1b2c3d4e5f"
    error_message = "arn must be the connection ARN"
  }

  assert {
    condition     = output.status == "PENDING"
    error_message = "status must be the connection status"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "rejects_self_managed_without_host" {
  command = plan

  variables {
    provider_type = "GitLabSelfManaged"
  }

  expect_failures = [var.host_arn]
}

run "rejects_github_enterprise_server_without_host" {
  command = plan

  variables {
    provider_type = "GitHubEnterpriseServer"
  }

  expect_failures = [var.host_arn]
}

run "rejects_github_with_host" {
  command = plan

  variables {
    host_arn = "arn:aws:codeconnections:ap-northeast-1:111111111111:host/alpha-gitlab-0123abcd"
  }

  expect_failures = [var.host_arn]
}

run "rejects_malformed_host_arn" {
  command = plan

  variables {
    provider_type = "GitLabSelfManaged"
    host_arn      = "arn:aws:codeconnections:ap-northeast-1:111111111111:connection/0a1b2c3d"
  }

  expect_failures = [var.host_arn]
}

run "rejects_name_of_33_chars" {
  command = plan

  variables {
    name = "a${join("", [for i in range(32) : "b"])}"
  }

  expect_failures = [var.name]
}

run "rejects_empty_name" {
  command = plan

  variables {
    name = ""
  }

  expect_failures = [var.name]
}

run "rejects_unknown_provider_type" {
  command = plan

  variables {
    provider_type = "github"
  }

  expect_failures = [var.provider_type]
}

run "rejects_malformed_region" {
  command = plan

  variables {
    region = "ap_northeast_1"
  }

  expect_failures = [var.region]
}
