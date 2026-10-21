mock_provider "aws" {}

variables {
  name               = "alpha-dev"
  subnet_ids         = ["subnet-aaa", "subnet-bbb"]
  security_group_ids = ["sg-aaa"]
  sns_topic_arns     = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms", "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-oncall"]
  vpc_id             = "vpc-0123456789abcdef0"
  target_groups = {
    web = { port = 8080 }
    api = { port = 9090 }
  }
}

run "one_alarm_per_target_group" {
  command = apply

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.unhealthy_hosts) == 2
    error_message = "One UnHealthyHostCount alarm per target group"
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.unhealthy_hosts["web"].alarm_name == "alpha-dev-web-unhealthy-hosts" &&
      aws_cloudwatch_metric_alarm.unhealthy_hosts["web"].namespace == "AWS/NetworkELB" &&
      aws_cloudwatch_metric_alarm.unhealthy_hosts["web"].metric_name == "UnHealthyHostCount" &&
      aws_cloudwatch_metric_alarm.unhealthy_hosts["web"].statistic == "Maximum" &&
      aws_cloudwatch_metric_alarm.unhealthy_hosts["web"].comparison_operator == "GreaterThanThreshold" &&
      aws_cloudwatch_metric_alarm.unhealthy_hosts["web"].threshold == 0 &&
      aws_cloudwatch_metric_alarm.unhealthy_hosts["web"].period == 60 &&
      aws_cloudwatch_metric_alarm.unhealthy_hosts["web"].evaluation_periods == 1
    )
    error_message = "Alarm must be UnHealthyHostCount > 0 over one 60 second period"
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.unhealthy_hosts["web"].dimensions["TargetGroup"] == aws_lb_target_group.this["web"].arn_suffix &&
      aws_cloudwatch_metric_alarm.unhealthy_hosts["web"].dimensions["LoadBalancer"] == aws_lb.this.arn_suffix &&
      length(aws_cloudwatch_metric_alarm.unhealthy_hosts["web"].dimensions) == 2
    )
    error_message = "Dimensions are the target group and load balancer arn suffixes"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.unhealthy_hosts["api"].dimensions["TargetGroup"] == aws_lb_target_group.this["api"].arn_suffix
    error_message = "Each alarm uses its own target group"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.unhealthy_hosts["web"].treat_missing_data == "notBreaching"
    error_message = "Missing data means no registered targets and must not alarm"
  }

  assert {
    condition     = toset(aws_cloudwatch_metric_alarm.unhealthy_hosts["web"].alarm_actions) == toset(var.sns_topic_arns) && toset(aws_cloudwatch_metric_alarm.unhealthy_hosts["web"].ok_actions) == toset(var.sns_topic_arns)
    error_message = "alarm_actions and ok_actions both go to sns_topic_arns"
  }
}

run "alarm_outputs" {
  command = apply

  assert {
    condition     = output.alarm_arns == { for k, a in aws_cloudwatch_metric_alarm.unhealthy_hosts : k => a.arn } && length(output.alarm_arns) == 2
    error_message = "alarm_arns is keyed by the target_groups key"
  }

  assert {
    condition     = output.target_group_arns == { for k, t in aws_lb_target_group.this : k => t.arn } && output.target_group_arn_suffixes == { for k, t in aws_lb_target_group.this : k => t.arn_suffix }
    error_message = "target group outputs are keyed by the target_groups key"
  }
}

run "no_alarm_without_target_group" {
  command = plan

  variables {
    target_groups = {}
    vpc_id        = null
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.unhealthy_hosts) == 0
    error_message = "No target group, no alarm"
  }
}
