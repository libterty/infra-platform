mock_provider "aws" {}

variables {
  name           = "alpha-api"
  cluster_name   = "alpha-dev"
  service_name   = "alpha-api"
  sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
}

run "no_dashboard_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_dashboard.this) == 0
    error_message = "dashboard_name = null must create no dashboard"
  }

  assert {
    condition     = output.dashboard_arn == null
    error_message = "dashboard_arn must be null when no dashboard exists"
  }
}

run "dashboard_body_is_valid_json" {
  command = plan

  variables {
    dashboard_name = "alpha-api"
  }

  assert {
    condition     = length(aws_cloudwatch_dashboard.this) == 1 && aws_cloudwatch_dashboard.this[0].dashboard_name == "alpha-api"
    error_message = "A name must create one dashboard"
  }

  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.this[0].dashboard_body).widgets) > 0
    error_message = "dashboard_body must be JSON with widgets"
  }

  assert {
    condition     = alltrue([for w in jsondecode(aws_cloudwatch_dashboard.this[0].dashboard_body).widgets : contains(flatten([for m in w.properties.metrics : m]), "alpha-api")])
    error_message = "Every widget must reference the service name"
  }
}

run "dashboard_without_lb" {
  command = plan

  variables {
    dashboard_name = "alpha-api"
  }

  assert {
    condition     = !strcontains(aws_cloudwatch_dashboard.this[0].dashboard_body, "AWS/ApplicationELB")
    error_message = "Without a load balancer there must be no ALB widget"
  }
}

run "dashboard_with_lb" {
  command = plan

  variables {
    dashboard_name = "alpha-api"
    load_balancer  = { alb_arn_suffix = "app/alpha/abc", target_group_arn_suffix = "targetgroup/alpha-api/def" }
  }

  assert {
    condition     = strcontains(aws_cloudwatch_dashboard.this[0].dashboard_body, "AWS/ApplicationELB") && strcontains(aws_cloudwatch_dashboard.this[0].dashboard_body, "targetgroup/alpha-api/def")
    error_message = "With a load balancer the dashboard must include ALB widgets for the target group"
  }
}
