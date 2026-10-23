mock_provider "aws" {}

variables {
  project                   = "example"
  env                       = "dev"
  expected_account_id       = "111111111111"
  origin_verify_header_name = "X-Origin-Verify"
  # A throwaway value for the tests; real values come from TF_VAR_origin_verify_header_value and never from a file.
  origin_verify_header_value = "test-only-origin-secret"
  origin_verify_host_headers = ["api.dev.example.com"]
}

# log-delivery checks that the ALB is in the current account.
override_data {
  target = module.alb_access_logs.data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

override_module {
  target = module.shared
  outputs = {
    strings = {
      vpc_id          = "vpc-0123456789abcdef0"
      alb_sg_id       = "sg-0123456789abcdef0"
      alarm_topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
      ecr_repository_urls = jsonencode({
        api               = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api"
        "traffic-breaker" = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-traffic-breaker"
      })
    }
    lists = {
      public_subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
    }
  }
}

# The canary of design v4 §6.1: off by default, a second target group and weighted api rules when set, and the
# lb-traffic-breaker that moves all traffic back to the stable target group when the canary misbehaves.

# lb-traffic-breaker validates real-looking ARNs, which the mock would not produce.
override_module {
  target = module.alb
  outputs = {
    alb_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:loadbalancer/app/example-dev-alb/0123456789abcdef"
    alb_arn_suffix = "app/example-dev-alb/0123456789abcdef"
    target_group_arns = {
      api          = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/example-dev-alb-api/0123456789abcdef"
      "api-canary" = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/example-dev-alb-api-canary/fedcba9876543210"
    }
    target_group_arn_suffixes = {
      api          = "targetgroup/example-dev-alb-api/0123456789abcdef"
      "api-canary" = "targetgroup/example-dev-alb-api-canary/fedcba9876543210"
    }
    listener_rule_arns = {
      api_stream = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/example-dev-alb/0123456789abcdef/1111111111111111/aaaaaaaaaaaaaaa1"
      api_quota  = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/example-dev-alb/0123456789abcdef/1111111111111111/aaaaaaaaaaaaaaa2"
      api_admin  = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/example-dev-alb/0123456789abcdef/1111111111111111/aaaaaaaaaaaaaaa3"
    }
  }
}

# The breaker builds the alarm ARNs for the Lambda permissions from these.
override_data {
  target = module.breaker[0].data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

override_data {
  target = module.breaker[0].data.aws_partition.current
  values = { partition = "aws" }
}

override_data {
  target = module.breaker[0].data.aws_region.current
  values = { region = "ap-northeast-1" }
}

run "canary_off_creates_nothing_extra" {
  command = plan

  assert {
    condition     = toset(keys(local.target_groups)) == toset(["api"])
    error_message = "Without canary there is one target group"
  }

  assert {
    condition     = alltrue([for k, r in local.listener_rules : r.target_group == "api" && r.forward == null])
    error_message = "Without canary every rule forwards to the api target group alone"
  }

  assert {
    condition     = length(module.breaker) == 0 && length(module.breaker_role) == 0 && length(module.breaker_function) == 0
    error_message = "No breaker, role, function or alarm without canary (design v4 K8)"
  }

  assert {
    condition     = !contains(keys(local.canary_strings), "api_canary_target_group_arn")
    error_message = "Nothing about a canary is published"
  }
}

run "canary_at_zero_weight_needs_no_breaker" {
  command = plan

  variables {
    canary = { weight = 0 }
  }

  assert {
    condition     = toset(keys(local.target_groups)) == toset(["api", "api-canary"]) && local.target_groups["api-canary"] == local.target_groups["api"]
    error_message = "The canary target group is a copy of the api one"
  }

  assert {
    condition = alltrue([
      for k in ["api_stream", "api_quota", "api_admin"] :
      local.listener_rules[k].target_group == null && local.listener_rules[k].forward.targets == {
        stable = { target_group = "api", target_group_arn = null, weight = 100 }
        canary = { target_group = "api-canary", target_group_arn = null, weight = 0 }
      }
    ])
    error_message = "The three api rules forward to both target groups by weight; the canary starts at 0"
  }

  assert {
    condition     = length(module.breaker) == 0
    error_message = "A canary that gets no traffic needs no breaker"
  }

  assert {
    condition     = local.canary_strings == tomap({ api_canary_target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/example-dev-alb-api-canary/fedcba9876543210" })
    error_message = "CI binds the canary release to this ARN (deploy/values-from-ssm.sh --canary)"
  }
}

run "rejects_weight_without_a_breaker" {
  command = plan

  variables {
    canary = { weight = 10 }
  }

  expect_failures = [var.canary]
}

run "rejects_a_weight_above_100" {
  command = plan

  variables {
    canary = { weight = 101, breaker = { image_tag = "0.1.0" } }
  }

  expect_failures = [var.canary]
}

run "rejects_the_latest_breaker_tag" {
  command = plan

  variables {
    canary = { weight = 10, breaker = { image_tag = "latest" } }
  }

  expect_failures = [var.canary]
}

run "canary_with_breaker_wires_the_alarms_to_the_lambda" {
  command = plan

  variables {
    canary = { weight = 10, breaker = { image_tag = "0.1.0" } }
  }

  assert {
    condition = alltrue([
      for k in ["api_stream", "api_quota", "api_admin"] :
      local.listener_rules[k].forward.targets.stable.weight == 90 && local.listener_rules[k].forward.targets.canary.weight == 10
    ])
    error_message = "stable gets 100 - weight, the canary gets weight"
  }

  assert {
    condition = local.breakers == tomap({
      for k, n in { api-stream         = "aaaaaaaaaaaaaaa1", api-quota = "aaaaaaaaaaaaaaa2", api-admin = "aaaaaaaaaaaaaaa3" } : k => {
        rule_arn                       = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/example-dev-alb/0123456789abcdef/1111111111111111/${n}"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/example-dev-alb-api/0123456789abcdef"
        canary_target_group_arn_suffix = "targetgroup/example-dev-alb-api-canary/fedcba9876543210"
        error_rate_percent             = 5
        min_requests                   = 50
        min_healthy_hosts              = 1
      }
    })
    error_message = "One breaker per weighted api rule, watching the canary target group and falling back to the stable one"
  }

  assert {
    condition     = module.breaker_function[0].function_name == "example-dev-traffic-breaker" && local.breaker_image_uri == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-traffic-breaker:0.1.0"
    error_message = "The breaker Lambda runs the traffic-breaker image from containerimage"
  }

  assert {
    condition = toset(flatten([for s in jsondecode(local.breaker_policy).Statement : s.Resource if contains(s.Action, "elasticloadbalancing:ModifyRule")])) == toset([
      "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/example-dev-alb/0123456789abcdef/1111111111111111/aaaaaaaaaaaaaaa1",
      "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/example-dev-alb/0123456789abcdef/1111111111111111/aaaaaaaaaaaaaaa2",
      "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/example-dev-alb/0123456789abcdef/1111111111111111/aaaaaaaaaaaaaaa3",
    ])
    error_message = "The breaker may rewrite only the three weighted api rules"
  }

  assert {
    condition     = !anytrue([for s in jsondecode(local.breaker_policy).Statement : contains(s.Action, "elasticloadbalancing:ModifyListener")])
    error_message = "The breaker never touches the listener default action"
  }
}
