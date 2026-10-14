mock_provider "aws" {}

variables {
  name = "alpha-dev"
}

run "defaults" {
  command = plan

  assert {
    condition     = one([for s in aws_ecs_cluster.this.setting : s.value if s.name == "containerInsights"]) == "enhanced"
    error_message = "containerInsights must default to enhanced"
  }

  assert {
    condition     = aws_ecs_cluster.this.name == "alpha-dev"
    error_message = "Cluster name must equal the name input"
  }

  assert {
    condition     = toset(aws_ecs_cluster_capacity_providers.this.capacity_providers) == toset(["FARGATE", "FARGATE_SPOT"])
    error_message = "Both FARGATE and FARGATE_SPOT must be attached"
  }

  assert {
    condition = (
      length(aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy) == 1 &&
      one(aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy).capacity_provider == "FARGATE" &&
      one(aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy).weight == 1 &&
      one(aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy).base == 0
    )
    error_message = "Default strategy must be FARGATE weight 1 base 0"
  }

  assert {
    condition     = aws_ecs_cluster.this.tags == tomap({ Name = "alpha-dev" })
    error_message = "Without tags input the only tag is Name"
  }
}

run "strategy_override_is_applied" {
  command = plan

  variables {
    default_capacity_provider_strategy = [
      { capacity_provider = "FARGATE", weight = 1, base = 1 },
      { capacity_provider = "FARGATE_SPOT", weight = 3 },
    ]
  }

  assert {
    condition     = length(aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy) == 2
    error_message = "Both strategy entries must be passed through"
  }

  assert {
    condition     = one([for s in aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy : s.weight if s.capacity_provider == "FARGATE_SPOT"]) == 3
    error_message = "FARGATE_SPOT weight must be 3"
  }
}

run "insights_log_group_when_enabled" {
  command = plan

  variables {
    log_retention_days = 14
    log_kms_key_arn    = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.container_insights) == 1
    error_message = "Default must create the performance log group"
  }

  assert {
    condition     = aws_cloudwatch_log_group.container_insights[0].name == "/aws/ecs/containerinsights/alpha-dev/performance"
    error_message = "Log group name must follow the Container Insights convention"
  }

  assert {
    condition     = aws_cloudwatch_log_group.container_insights[0].retention_in_days == 14
    error_message = "Retention must equal log_retention_days"
  }

  assert {
    condition     = aws_cloudwatch_log_group.container_insights[0].kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    error_message = "log_kms_key_arn must be passed to the log group"
  }
}

run "enabled_level_also_creates_log_group" {
  command = plan

  variables {
    container_insights = "enabled"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.container_insights) == 1
    error_message = "enabled must also create the performance log group"
  }
}

run "no_insights_log_group_when_disabled" {
  command = plan

  variables {
    container_insights = "disabled"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.container_insights) == 0
    error_message = "disabled must not create the performance log group"
  }

  assert {
    condition     = one([for s in aws_ecs_cluster.this.setting : s.value if s.name == "containerInsights"]) == "disabled"
    error_message = "containerInsights must be disabled"
  }
}

run "no_namespace_by_default" {
  command = plan

  assert {
    condition     = length(aws_service_discovery_http_namespace.this) == 0
    error_message = "No namespace without service_connect_namespace"
  }

  assert {
    condition     = output.service_connect_namespace_arn == null
    error_message = "Namespace ARN output must be null when none is created"
  }
}

run "namespace_when_named" {
  command = plan

  variables {
    service_connect_namespace = "alpha.local"
  }

  assert {
    condition     = length(aws_service_discovery_http_namespace.this) == 1
    error_message = "A named namespace must be created"
  }

  assert {
    condition     = aws_service_discovery_http_namespace.this[0].name == "alpha.local"
    error_message = "Namespace name must equal the input"
  }
}

run "outputs_expose_cluster" {
  command = plan

  override_resource {
    target          = aws_ecs_cluster.this
    override_during = plan
    values = {
      arn = "arn:aws:ecs:ap-northeast-1:111111111111:cluster/alpha-dev"
      id  = "arn:aws:ecs:ap-northeast-1:111111111111:cluster/alpha-dev"
    }
  }

  assert {
    condition     = output.cluster_name == "alpha-dev"
    error_message = "cluster_name output must equal the name"
  }

  assert {
    condition     = output.cluster_arn == "arn:aws:ecs:ap-northeast-1:111111111111:cluster/alpha-dev"
    error_message = "cluster_arn output must expose the cluster ARN"
  }

  assert {
    condition     = output.cluster_id == "arn:aws:ecs:ap-northeast-1:111111111111:cluster/alpha-dev"
    error_message = "cluster_id output must expose the cluster id"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_ecs_cluster.this.tags == tomap({ Project = "alpha", Name = "alpha-dev" })
    error_message = "tags input must be merged with Name"
  }

  assert {
    condition     = aws_cloudwatch_log_group.container_insights[0].tags == tomap({ Project = "alpha", Name = "/aws/ecs/containerinsights/alpha-dev/performance" })
    error_message = "Log group must carry tags and its own Name"
  }
}

run "name_rejects_uppercase" {
  command = plan
  variables { name = "Alpha" }
  expect_failures = [var.name]
}

run "name_rejects_leading_digit" {
  command = plan
  variables { name = "1alpha" }
  expect_failures = [var.name]
}

run "name_rejects_64_chars" {
  command = plan
  variables { name = replace(format("%64s", ""), " ", "a") }
  expect_failures = [var.name]
}

run "name_accepts_two_chars" {
  command = plan
  variables { name = "ab" }

  assert {
    condition     = aws_ecs_cluster.this.name == "ab"
    error_message = "A 2-char name must be accepted"
  }
}

run "name_accepts_63_chars" {
  command = plan
  variables { name = replace(format("%63s", ""), " ", "a") }

  assert {
    condition     = length(aws_ecs_cluster.this.name) == 63
    error_message = "A 63-char name must be accepted"
  }
}

run "container_insights_rejects_on" {
  command = plan
  variables { container_insights = "on" }
  expect_failures = [var.container_insights]
}

run "container_insights_accepts_enabled" {
  command = plan
  variables { container_insights = "enabled" }

  assert {
    condition     = one([for s in aws_ecs_cluster.this.setting : s.value if s.name == "containerInsights"]) == "enabled"
    error_message = "enabled must be accepted"
  }
}

run "capacity_provider_rejects_ec2" {
  command = plan
  variables {
    default_capacity_provider_strategy = [{ capacity_provider = "EC2" }]
  }
  expect_failures = [var.default_capacity_provider_strategy]
}

run "capacity_provider_rejects_empty_strategy" {
  command = plan
  variables {
    default_capacity_provider_strategy = []
  }
  expect_failures = [var.default_capacity_provider_strategy]
}

run "only_one_base_rejects_two" {
  command = plan
  variables {
    default_capacity_provider_strategy = [
      { capacity_provider = "FARGATE", base = 1 },
      { capacity_provider = "FARGATE_SPOT", base = 1 },
    ]
  }
  expect_failures = [var.default_capacity_provider_strategy]
}

run "only_one_base_accepts_one" {
  command = plan
  variables {
    default_capacity_provider_strategy = [
      { capacity_provider = "FARGATE", base = 1 },
      { capacity_provider = "FARGATE_SPOT" },
    ]
  }

  assert {
    condition     = one([for s in aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy : s.base if s.capacity_provider == "FARGATE"]) == 1
    error_message = "A single base must be accepted"
  }
}

run "retention_rejects_10" {
  command = plan
  variables { log_retention_days = 10 }
  expect_failures = [var.log_retention_days]
}

run "retention_accepts_30" {
  command = plan
  variables { log_retention_days = 30 }

  assert {
    condition     = aws_cloudwatch_log_group.container_insights[0].retention_in_days == 30
    error_message = "30 must be accepted"
  }
}
