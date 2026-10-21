mock_provider "aws" {}

variables {
  name               = "alpha-dev"
  subnet_ids         = ["subnet-aaa", "subnet-bbb"]
  security_group_ids = ["sg-aaa"]
  sns_topic_arns     = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
}

run "defaults_are_internal_cross_zone_and_protected" {
  command = plan

  assert {
    condition     = aws_lb.this.load_balancer_type == "network"
    error_message = "Must be a network load balancer"
  }

  assert {
    condition     = aws_lb.this.name == "alpha-dev"
    error_message = "name is used as is"
  }

  assert {
    condition     = aws_lb.this.internal == true
    error_message = "internal defaults to true"
  }

  assert {
    condition     = aws_lb.this.enable_cross_zone_load_balancing == true
    error_message = "cross_zone defaults to true"
  }

  assert {
    condition     = aws_lb.this.enable_deletion_protection == true
    error_message = "deletion_protection defaults to true"
  }

  assert {
    condition     = toset(aws_lb.this.subnets) == toset(["subnet-aaa", "subnet-bbb"]) && aws_lb.this.security_groups == toset(["sg-aaa"])
    error_message = "subnets and security groups are passed through"
  }

  assert {
    condition     = length(aws_lb.this.access_logs) == 0
    error_message = "No access_logs block by default"
  }

  assert {
    condition     = aws_lb.this.tags["Name"] == "alpha-dev"
    error_message = "Name tag is added"
  }
}

run "options_are_passed_through" {
  command = plan

  variables {
    internal            = false
    cross_zone          = false
    deletion_protection = false
    tags                = { Project = "alpha" }
  }

  assert {
    condition     = aws_lb.this.internal == false && aws_lb.this.enable_cross_zone_load_balancing == false && aws_lb.this.enable_deletion_protection == false
    error_message = "internal, cross_zone and deletion_protection must follow the variables"
  }

  assert {
    condition     = aws_lb.this.tags["Project"] == "alpha" && aws_lb.this.tags["Name"] == "alpha-dev"
    error_message = "tags merge with Name"
  }
}

run "access_logs_enabled" {
  command = plan

  variables {
    access_logs = { bucket = "alpha-dev-nlb-logs", prefix = "nlb" }
  }

  assert {
    condition     = aws_lb.this.access_logs[0].enabled == true && aws_lb.this.access_logs[0].bucket == "alpha-dev-nlb-logs" && aws_lb.this.access_logs[0].prefix == "nlb"
    error_message = "access_logs must be enabled with the given bucket and prefix"
  }
}

run "access_logs_prefix_optional" {
  command = plan

  variables {
    access_logs = { bucket = "alpha-dev-nlb-logs" }
  }

  assert {
    condition     = aws_lb.this.access_logs[0].bucket == "alpha-dev-nlb-logs"
    error_message = "prefix may be omitted"
  }
}

run "outputs_of_load_balancer" {
  command = apply

  assert {
    condition     = output.nlb_arn == aws_lb.this.arn && output.nlb_arn_suffix == aws_lb.this.arn_suffix && output.dns_name == aws_lb.this.dns_name && output.zone_id == aws_lb.this.zone_id
    error_message = "Load balancer outputs must come from aws_lb.this"
  }

  assert {
    condition     = output.listener_arns == {} && output.target_group_arns == {} && output.target_group_arn_suffixes == {} && output.alarm_arns == {}
    error_message = "Without target groups and listeners the maps are empty"
  }
}
