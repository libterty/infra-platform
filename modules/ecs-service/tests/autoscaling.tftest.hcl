mock_provider "aws" {}

variables {
  name               = "alpha-api"
  cluster_arn        = "arn:aws:ecs:ap-northeast-1:111111111111:cluster/alpha-dev"
  image              = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-api:1.0.0"
  execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-ecs-execution"
  task_role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-alpha-api-task"
  network = {
    subnet_ids         = ["subnet-aaa", "subnet-bbb"]
    security_group_ids = ["sg-111"]
  }
}

run "fixed_count_when_autoscaling_null" {
  command = plan

  variables {
    desired_count = 3
  }

  assert {
    condition     = aws_appautoscaling_target.this.min_capacity == 3 && aws_appautoscaling_target.this.max_capacity == 3
    error_message = "autoscaling = null must pin min = max = desired_count"
  }

  assert {
    condition     = length(aws_appautoscaling_policy.cpu) == 0 && length(aws_appautoscaling_policy.requests) == 0 && length(aws_appautoscaling_policy.step) == 0 && length(aws_cloudwatch_metric_alarm.scaling) == 0
    error_message = "No policy or scaling alarm without autoscaling"
  }
}

run "target_tracking_is_default_policy" {
  command = plan

  variables {
    autoscaling = { min_capacity = 2, max_capacity = 6 }
  }

  assert {
    condition     = aws_appautoscaling_target.this.min_capacity == 2 && aws_appautoscaling_target.this.max_capacity == 6
    error_message = "Capacity range must pass through"
  }

  assert {
    condition     = length(aws_appautoscaling_policy.cpu) == 1 && aws_appautoscaling_policy.cpu[0].policy_type == "TargetTrackingScaling"
    error_message = "Default policy must be CPU target tracking"
  }

  assert {
    condition     = one(aws_appautoscaling_policy.cpu[0].target_tracking_scaling_policy_configuration).target_value == 60
    error_message = "CPU target must default to 60"
  }

  assert {
    condition     = one(aws_appautoscaling_policy.cpu[0].target_tracking_scaling_policy_configuration).scale_in_cooldown == 300 && one(aws_appautoscaling_policy.cpu[0].target_tracking_scaling_policy_configuration).scale_out_cooldown == 60
    error_message = "Cooldowns must default to 300/60"
  }

  assert {
    condition     = length(aws_appautoscaling_policy.requests) == 0 && length(aws_appautoscaling_policy.step) == 0 && length(aws_cloudwatch_metric_alarm.scaling) == 0
    error_message = "Requests and step resources must not exist"
  }
}

run "requests_policy_only_when_set" {
  command = plan

  variables {
    container_port = 8000
    autoscaling = {
      min_capacity    = 2
      max_capacity    = 6
      target_tracking = { requests_per_target = 300 }
    }
    load_balancer = {
      target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef"
      alb_arn_suffix   = "app/alpha-alb/fedcba9876543210"
    }
  }

  assert {
    condition     = length(aws_appautoscaling_policy.requests) == 1 && length(aws_appautoscaling_policy.cpu) == 1
    error_message = "requests must be added next to cpu"
  }

  assert {
    condition     = one(aws_appautoscaling_policy.requests[0].target_tracking_scaling_policy_configuration).target_value == 300
    error_message = "requests target must be 300"
  }

  assert {
    condition     = one(one(aws_appautoscaling_policy.requests[0].target_tracking_scaling_policy_configuration).predefined_metric_specification).resource_label == "app/alpha-alb/fedcba9876543210/targetgroup/alpha-api-8000/0123456789abcdef"
    error_message = "resource_label must be <alb suffix>/<target group suffix>"
  }
}

run "step_policy_has_no_target_tracking" {
  command = plan

  variables {
    autoscaling = { min_capacity = 2, max_capacity = 6, policy = "step" }
  }

  override_resource {
    target          = aws_appautoscaling_policy.step["cpu_scale_out"]
    override_during = plan
    values          = { arn = "arn:aws:autoscaling:ap-northeast-1:111111111111:scalingPolicy:1:resource/ecs/service/alpha-dev/alpha-api:policyName/cpu-out" }
  }

  override_resource {
    target          = aws_appautoscaling_policy.step["cpu_scale_in"]
    override_during = plan
    values          = { arn = "arn:aws:autoscaling:ap-northeast-1:111111111111:scalingPolicy:2:resource/ecs/service/alpha-dev/alpha-api:policyName/cpu-in" }
  }

  override_resource {
    target          = aws_appautoscaling_policy.step["memory_scale_out"]
    override_during = plan
    values          = { arn = "arn:aws:autoscaling:ap-northeast-1:111111111111:scalingPolicy:3:resource/ecs/service/alpha-dev/alpha-api:policyName/mem-out" }
  }

  override_resource {
    target          = aws_appautoscaling_policy.step["memory_scale_in"]
    override_during = plan
    values          = { arn = "arn:aws:autoscaling:ap-northeast-1:111111111111:scalingPolicy:4:resource/ecs/service/alpha-dev/alpha-api:policyName/mem-in" }
  }

  assert {
    condition     = length(aws_appautoscaling_policy.cpu) == 0 && length(aws_appautoscaling_policy.requests) == 0
    error_message = "step must not create target tracking policies"
  }

  assert {
    condition     = toset(keys(aws_appautoscaling_policy.step)) == toset(["cpu_scale_out", "cpu_scale_in", "memory_scale_out", "memory_scale_in"])
    error_message = "step must create cpu and memory, in and out"
  }

  assert {
    condition = (
      { for s in one(aws_appautoscaling_policy.step["cpu_scale_out"].step_scaling_policy_configuration).step_adjustment : s.scaling_adjustment => [s.metric_interval_lower_bound, coalesce(s.metric_interval_upper_bound, "none")] }
      == { 1 = ["0", "10"], 2 = ["10", "20"], 3 = ["20", "none"] }
    )
    error_message = "Scale-out must be +1/+2/+3 in steps of 10"
  }

  assert {
    condition     = [for s in one(aws_appautoscaling_policy.step["memory_scale_in"].step_scaling_policy_configuration).step_adjustment : s.scaling_adjustment] == [-1]
    error_message = "Scale-in must be -1"
  }

  assert {
    condition     = one(aws_appautoscaling_policy.step["cpu_scale_out"].step_scaling_policy_configuration).cooldown == 180 && one(aws_appautoscaling_policy.step["cpu_scale_in"].step_scaling_policy_configuration).cooldown == 300
    error_message = "Cooldowns must be 180 out and 300 in"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.scaling["cpu_scale_out"].threshold == 70 && aws_cloudwatch_metric_alarm.scaling["cpu_scale_in"].threshold == 40 && aws_cloudwatch_metric_alarm.scaling["memory_scale_out"].threshold == 70 && aws_cloudwatch_metric_alarm.scaling["memory_scale_in"].threshold == 50
    error_message = "Thresholds must be 70/40 and 70/50"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.scaling["cpu_scale_out"].alarm_actions == toset(["arn:aws:autoscaling:ap-northeast-1:111111111111:scalingPolicy:1:resource/ecs/service/alpha-dev/alpha-api:policyName/cpu-out"])
    error_message = "cpu scale-out alarm must act on its own policy"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.scaling["memory_scale_in"].alarm_actions == toset(["arn:aws:autoscaling:ap-northeast-1:111111111111:scalingPolicy:4:resource/ecs/service/alpha-dev/alpha-api:policyName/mem-in"])
    error_message = "memory scale-in alarm must act on its own policy"
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.scaling["cpu_scale_out"].comparison_operator == "GreaterThanOrEqualToThreshold" &&
      aws_cloudwatch_metric_alarm.scaling["cpu_scale_in"].comparison_operator == "LessThanThreshold" &&
      aws_cloudwatch_metric_alarm.scaling["memory_scale_out"].comparison_operator == "GreaterThanOrEqualToThreshold" &&
      aws_cloudwatch_metric_alarm.scaling["memory_scale_in"].comparison_operator == "LessThanOrEqualToThreshold"
    )
    error_message = "Comparison operators must follow the project-c alarm definitions"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.scaling["cpu_scale_out"].evaluation_periods == 1 && aws_cloudwatch_metric_alarm.scaling["cpu_scale_in"].evaluation_periods == 5
    error_message = "Evaluation must be 1 minute out and 5 minutes in"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.scaling["memory_scale_out"].metric_name == "MemoryUtilization" && aws_cloudwatch_metric_alarm.scaling["cpu_scale_out"].metric_name == "CPUUtilization"
    error_message = "Alarms must watch the right metric"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.scaling["cpu_scale_out"].dimensions == tomap({ ClusterName = "alpha-dev", ServiceName = "alpha-api" })
    error_message = "Alarm dimensions must be cluster and service"
  }
}

run "step_thresholds_are_configurable" {
  command = plan

  variables {
    autoscaling = {
      min_capacity = 2
      max_capacity = 6
      policy       = "step"
      step         = { cpu_scale_out_threshold = 80, scale_out_step_size = 5 }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.scaling["cpu_scale_out"].threshold == 80
    error_message = "cpu_scale_out_threshold must be configurable"
  }

  assert {
    condition     = contains([for s in one(aws_appautoscaling_policy.step["cpu_scale_out"].step_scaling_policy_configuration).step_adjustment : s.metric_interval_upper_bound], "5")
    error_message = "scale_out_step_size must change the step bounds"
  }
}

run "scalable_target_resource_id" {
  command = plan

  assert {
    condition     = aws_appautoscaling_target.this.resource_id == "service/alpha-dev/alpha-api"
    error_message = "resource_id must be service/<cluster_name>/<service_name>"
  }

  assert {
    condition     = aws_appautoscaling_target.this.scalable_dimension == "ecs:service:DesiredCount" && aws_appautoscaling_target.this.service_namespace == "ecs"
    error_message = "Scalable dimension must be the ECS desired count"
  }
}

run "policy_rejects_scheduled" {
  command = plan
  variables {
    autoscaling = { min_capacity = 1, max_capacity = 3, policy = "scheduled" }
  }
  expect_failures = [var.autoscaling]
}

run "capacity_rejects_min_above_max" {
  command = plan
  variables {
    autoscaling = { min_capacity = 4, max_capacity = 2 }
  }
  expect_failures = [var.autoscaling]
}

run "capacity_rejects_min_zero" {
  command = plan
  variables {
    desired_count = 0
    autoscaling   = { min_capacity = 0, max_capacity = 2 }
  }
  expect_failures = [var.autoscaling]
}

run "capacity_accepts_min_equals_max_one" {
  command = plan
  variables {
    desired_count = 1
    autoscaling   = { min_capacity = 1, max_capacity = 1 }
  }

  assert {
    condition     = aws_appautoscaling_target.this.min_capacity == 1 && aws_appautoscaling_target.this.max_capacity == 1
    error_message = "min = max = 1 must be accepted"
  }
}

run "desired_rejects_above_max" {
  command = plan
  variables {
    desired_count = 5
    autoscaling   = { min_capacity = 1, max_capacity = 3 }
  }
  expect_failures = [var.autoscaling]
}

run "desired_rejects_below_min" {
  command = plan
  variables {
    desired_count = 1
    autoscaling   = { min_capacity = 2, max_capacity = 3 }
  }
  expect_failures = [var.autoscaling]
}

run "desired_accepts_within_range" {
  command = plan
  variables {
    desired_count = 3
    autoscaling   = { min_capacity = 1, max_capacity = 3 }
  }

  assert {
    condition     = aws_appautoscaling_target.this.max_capacity == 3
    error_message = "desired_count at the upper bound must be accepted"
  }
}

run "requests_requires_alb_suffix" {
  command = plan
  variables {
    container_port = 8000
    autoscaling = {
      min_capacity    = 1
      max_capacity    = 3
      target_tracking = { requests_per_target = 300 }
    }
    load_balancer = {
      target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef"
    }
  }
  expect_failures = [var.autoscaling]
}

run "requests_requires_load_balancer" {
  command = plan
  variables {
    autoscaling = {
      min_capacity    = 1
      max_capacity    = 3
      target_tracking = { requests_per_target = 300 }
    }
  }
  expect_failures = [var.autoscaling]
}
