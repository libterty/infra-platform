mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:loadbalancer/app/alpha-dev/0123456789abcdef"
      arn_suffix = "app/alpha-dev/0123456789abcdef"
    }
  }

  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/alpha-dev/0123456789abcdef/fedcba9876543210"
    }
  }
}

variables {
  name               = "alpha-dev"
  subnet_ids         = ["subnet-aaa", "subnet-bbb"]
  security_group_ids = ["sg-aaa"]
  sns_topic_arns     = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
}

run "load_balancer_defaults" {
  command = plan

  assert {
    condition     = aws_lb.this.internal == false && aws_lb.this.load_balancer_type == "application" && aws_lb.this.idle_timeout == 60
    error_message = "Defaults: external application ALB, idle 60"
  }

  assert {
    condition     = aws_lb.this.enable_deletion_protection == true && aws_lb.this.drop_invalid_header_fields == true
    error_message = "Deletion protection and drop_invalid_header_fields must default to true"
  }

  assert {
    condition     = toset(aws_lb.this.subnets) == toset(["subnet-aaa", "subnet-bbb"]) && toset(aws_lb.this.security_groups) == toset(["sg-aaa"])
    error_message = "Subnets and security groups must equal the inputs"
  }

  assert {
    condition     = aws_lb.this.tags == tomap({ Name = "alpha-dev" })
    error_message = "Only the Name tag by default"
  }
}

run "no_access_logs_by_default" {
  command = plan

  assert {
    condition     = length(aws_lb.this.access_logs) == 0
    error_message = "The classic access_logs block is gone; access logs go through log-delivery"
  }
}

run "no_waf_by_default" {
  command = plan

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 0
    error_message = "No association without web_acl_arn"
  }
}

run "waf_association_when_given" {
  command = plan

  variables {
    web_acl_arn = "arn:aws:wafv2:ap-northeast-1:111111111111:regional/webacl/alpha/abc"
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 1 && aws_wafv2_web_acl_association.this[0].web_acl_arn == "arn:aws:wafv2:ap-northeast-1:111111111111:regional/webacl/alpha/abc"
    error_message = "One association with the given Web ACL"
  }
}

run "elb_5xx_alarm" {
  command = apply

  assert {
    condition     = aws_cloudwatch_metric_alarm.elb_5xx.metric_name == "HTTPCode_ELB_5XX_Count" && aws_cloudwatch_metric_alarm.elb_5xx.threshold == 1 && aws_cloudwatch_metric_alarm.elb_5xx.period == 60
    error_message = "ELB 5xx alarm defaults: threshold 1, period 60"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.elb_5xx.alarm_actions == toset(var.sns_topic_arns) && aws_cloudwatch_metric_alarm.elb_5xx.ok_actions == toset(var.sns_topic_arns)
    error_message = "alarm_actions and ok_actions must both be the SNS topics"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.elb_5xx.dimensions == tomap({ LoadBalancer = aws_lb.this.arn_suffix })
    error_message = "Dimension LoadBalancer must be the ALB arn_suffix"
  }

  assert {
    condition     = output.alarm_arns == { elb_5xx = aws_cloudwatch_metric_alarm.elb_5xx.arn } && output.alb_arn_suffix == aws_lb.this.arn_suffix
    error_message = "alarm_arns must expose the alarm and alb_arn_suffix the ALB suffix"
  }
}

run "alarm_config_override" {
  command = plan

  variables {
    alarm_config = { elb_5xx_threshold = 5 }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.elb_5xx.threshold == 5 && aws_cloudwatch_metric_alarm.elb_5xx.period == 60
    error_message = "Threshold 5 overrides, period stays 60"
  }
}
