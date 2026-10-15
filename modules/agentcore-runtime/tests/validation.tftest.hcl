mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

variables {
  name          = "alpha_dev_agent"
  role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-agent-runtime"
  container_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-agent:1.4.2"
  network = {
    subnet_ids         = ["subnet-0aaa1111", "subnet-0bbb2222"]
    security_group_ids = ["sg-0ccc3333"]
  }
}

run "name_rejects_hyphen" {
  command = plan

  variables {
    name = "alpha-dev-agent"
  }

  expect_failures = [var.name]
}

run "name_accepts_underscore" {
  command = plan

  variables {
    name = "alpha_dev_agent_2"
  }
}

run "name_rejects_49_chars" {
  command = plan

  variables {
    name = "abbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }

  expect_failures = [var.name]
}

run "name_accepts_48_chars" {
  command = plan

  variables {
    name = "abbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }
}

run "name_rejects_leading_digit" {
  command = plan

  variables {
    name = "1alpha"
  }

  expect_failures = [var.name]
}

run "role_arn_accepts_path" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:role/service-role/alpha-dev-agent-runtime"
  }

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.this.role_arn == "arn:aws:iam::111111111111:role/service-role/alpha-dev-agent-runtime"
    error_message = "A role ARN with a path must pass"
  }
}

run "role_arn_accepts_nested_path" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:role/team/agents/alpha-dev-agent-runtime"
  }
}

run "role_arn_rejects_trailing_slash" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:role/service-role/"
  }

  expect_failures = [var.role_arn]
}

run "role_arn_rejects_empty_path_segment" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:role//alpha-dev-agent-runtime"
  }

  expect_failures = [var.role_arn]
}

run "role_arn_rejects_non_role" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:user/alpha"
  }

  expect_failures = [var.role_arn]
}

run "container_uri_rejects_latest" {
  command = plan

  variables {
    container_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-agent:latest"
  }

  expect_failures = [var.container_uri]
}

run "container_uri_accepts_explicit_tag" {
  command = plan

  variables {
    container_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-agent:2026.10.15-abc1234"
  }
}

run "container_uri_accepts_digest" {
  command = plan

  variables {
    container_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-agent@sha256:0000000000000000000000000000000000000000000000000000000000000000"
  }
}

run "container_uri_rejects_untagged" {
  command = plan

  variables {
    container_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-agent"
  }

  expect_failures = [var.container_uri]
}

run "container_uri_rejects_non_ecr" {
  command = plan

  variables {
    container_uri = "docker.io/library/python:3.12"
  }

  expect_failures = [var.container_uri]
}

run "lifecycle_rejects_idle_59" {
  command = plan

  variables {
    session_lifecycle = { idle_session_timeout = 59 }
  }

  expect_failures = [var.session_lifecycle]
}

run "lifecycle_accepts_idle_60" {
  command = plan

  variables {
    session_lifecycle = { idle_session_timeout = 60 }
  }
}

run "lifecycle_rejects_idle_1209601" {
  command = plan

  variables {
    session_lifecycle = { idle_session_timeout = 1209601, max_lifetime = 1209600 }
  }

  expect_failures = [var.session_lifecycle]
}

run "lifecycle_accepts_1209600" {
  command = plan

  variables {
    session_lifecycle = { idle_session_timeout = 1209600, max_lifetime = 1209600 }
  }
}

run "lifecycle_rejects_max_59" {
  command = plan

  variables {
    session_lifecycle = { idle_session_timeout = 60, max_lifetime = 59 }
  }

  expect_failures = [var.session_lifecycle]
}

run "lifecycle_accepts_max_60" {
  command = plan

  variables {
    session_lifecycle = { idle_session_timeout = 60, max_lifetime = 60 }
  }
}

run "lifecycle_rejects_max_1209601" {
  command = plan

  variables {
    session_lifecycle = { max_lifetime = 1209601 }
  }

  expect_failures = [var.session_lifecycle]
}

run "lifecycle_rejects_idle_above_max" {
  command = plan

  variables {
    session_lifecycle = { idle_session_timeout = 3601, max_lifetime = 3600 }
  }

  expect_failures = [var.session_lifecycle]
}

run "network_rejects_one_subnet" {
  command = plan

  variables {
    network = { subnet_ids = ["subnet-0aaa1111"], security_group_ids = ["sg-0ccc3333"] }
  }

  expect_failures = [var.network]
}

run "network_rejects_duplicate_subnets" {
  command = plan

  variables {
    network = { subnet_ids = ["subnet-0aaa1111", "subnet-0aaa1111"], security_group_ids = ["sg-0ccc3333"] }
  }

  expect_failures = [var.network]
}

run "network_accepts_two_subnets" {
  command = plan

  variables {
    network = { mode = "VPC", subnet_ids = ["subnet-0aaa1111", "subnet-0bbb2222"], security_group_ids = ["sg-0ccc3333"] }
  }
}

run "network_rejects_vpc_without_sg" {
  command = plan

  variables {
    network = { subnet_ids = ["subnet-0aaa1111", "subnet-0bbb2222"] }
  }

  expect_failures = [var.network]
}

run "network_rejects_six_sgs" {
  command = plan

  variables {
    network = { subnet_ids = ["subnet-0aaa1111", "subnet-0bbb2222"], security_group_ids = ["sg-01", "sg-02", "sg-03", "sg-04", "sg-05", "sg-06"] }
  }

  expect_failures = [var.network]
}

run "network_accepts_five_sgs" {
  command = plan

  variables {
    network = { subnet_ids = ["subnet-0aaa1111", "subnet-0bbb2222"], security_group_ids = ["sg-01", "sg-02", "sg-03", "sg-04", "sg-05"] }
  }
}

run "network_rejects_public_with_subnets" {
  command = plan

  variables {
    network = { mode = "PUBLIC", subnet_ids = ["subnet-0aaa1111", "subnet-0bbb2222"] }
  }

  expect_failures = [var.network]
}

run "network_rejects_public_with_sgs" {
  command = plan

  variables {
    network = { mode = "PUBLIC", security_group_ids = ["sg-0ccc3333"] }
  }

  expect_failures = [var.network]
}

run "network_accepts_public_empty" {
  command = plan

  variables {
    network = { mode = "PUBLIC" }
  }
}

run "network_rejects_unknown_mode" {
  command = plan

  variables {
    network = { mode = "PRIVATE", subnet_ids = ["subnet-0aaa1111", "subnet-0bbb2222"], security_group_ids = ["sg-0ccc3333"] }
  }

  expect_failures = [var.network]
}

run "protocol_rejects_grpc" {
  command = plan

  variables {
    protocol = "GRPC"
  }

  expect_failures = [var.protocol]
}

run "protocol_accepts_mcp" {
  command = plan

  variables {
    protocol = "MCP"
  }
}

run "jwt_rejects_http_discovery_url" {
  command = plan

  variables {
    jwt_authorizer = { discovery_url = "http://idp.example.com/realms/alpha/.well-known/openid-configuration", allowed_clients = ["alpha-web"] }
  }

  expect_failures = [var.jwt_authorizer]
}

run "jwt_rejects_missing_well_known" {
  command = plan

  variables {
    jwt_authorizer = { discovery_url = "https://idp.example.com/realms/alpha", allowed_clients = ["alpha-web"] }
  }

  expect_failures = [var.jwt_authorizer]
}

run "jwt_rejects_no_audience_or_clients" {
  command = plan

  variables {
    jwt_authorizer = { discovery_url = "https://idp.example.com/realms/alpha/.well-known/openid-configuration" }
  }

  expect_failures = [var.jwt_authorizer]
}

run "jwt_accepts_clients_only" {
  command = plan

  variables {
    jwt_authorizer = { discovery_url = "https://idp.example.com/realms/alpha/.well-known/openid-configuration", allowed_clients = ["alpha-web"] }
  }
}
