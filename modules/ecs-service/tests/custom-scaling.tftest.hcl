mock_provider "aws" {
  # Alarm actions are validated as ARNs, so the generated policy ARN must look like one under apply.
  mock_resource "aws_appautoscaling_policy" {
    defaults = {
      arn = "arn:aws:autoscaling:ap-northeast-1:111111111111:scalingPolicy:1:resource/ecs/service/alpha-dev/alpha-api:policyName/custom"
    }
  }
}

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

run "custom_policy_creates_no_builtin_policy_or_alarm" {
  command = plan

  variables {
    autoscaling = { min_capacity = 2, max_capacity = 6, policy = "custom" }
  }

  assert {
    condition     = length(aws_appautoscaling_policy.cpu) == 0
    error_message = "custom must not create the CPU target tracking policy"
  }

  assert {
    condition     = length(aws_appautoscaling_policy.requests) == 0
    error_message = "custom must not create the request count policy"
  }

  assert {
    condition     = length(aws_appautoscaling_policy.step) == 0
    error_message = "custom must not create the built-in step policies"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.scaling) == 0
    error_message = "custom must not create the built-in scaling alarms"
  }

  assert {
    condition     = aws_appautoscaling_target.this.min_capacity == 2 && aws_appautoscaling_target.this.max_capacity == 6
    error_message = "custom must still own the scalable target"
  }
}

run "default_policy_unchanged_and_no_custom_resources" {
  command = plan

  variables {
    autoscaling = { min_capacity = 2, max_capacity = 6 }
  }

  assert {
    condition     = length(aws_appautoscaling_policy.cpu) == 1
    error_message = "target_tracking default must keep the CPU policy"
  }

  assert {
    condition     = length(aws_appautoscaling_policy.custom_step) == 0 && length(aws_cloudwatch_metric_alarm.custom_step) == 0 && length(aws_appautoscaling_scheduled_action.this) == 0
    error_message = "No custom resources by default"
  }
}

run "metric_step_policy_creates_policy_and_alarm" {
  command = apply

  variables {
    autoscaling = {
      min_capacity = 1
      max_capacity = 10
      policy       = "custom"
      step_policies = {
        queue_depth_high = {
          comparison_operator = "GreaterThanOrEqualToThreshold"
          threshold           = 100
          evaluation_periods  = 2
          metric = {
            namespace   = "AWS/SQS"
            metric_name = "ApproximateNumberOfMessagesVisible"
            dimensions  = { QueueName = "alpha-dev-jobs" }
          }
          adjustments = [
            { lower = 0, upper = 100, change = 1 },
            { lower = 100, change = 3 },
          ]
        }
      }
    }
  }

  assert {
    condition     = aws_appautoscaling_policy.custom_step["queue_depth_high"].policy_type == "StepScaling"
    error_message = "A step policy must be StepScaling"
  }

  assert {
    condition = (
      { for s in one(aws_appautoscaling_policy.custom_step["queue_depth_high"].step_scaling_policy_configuration).step_adjustment : s.scaling_adjustment => [s.metric_interval_lower_bound, coalesce(s.metric_interval_upper_bound, "none")] }
      == { 1 = ["0", "100"], 3 = ["100", "none"] }
    )
    error_message = "Adjustments must map lower/upper/change to the step adjustment bounds and scaling_adjustment"
  }

  assert {
    condition     = one(aws_appautoscaling_policy.custom_step["queue_depth_high"].step_scaling_policy_configuration).adjustment_type == "ChangeInCapacity"
    error_message = "Adjustments are capacity changes"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.custom_step["queue_depth_high"].namespace == "AWS/SQS" && aws_cloudwatch_metric_alarm.custom_step["queue_depth_high"].metric_name == "ApproximateNumberOfMessagesVisible"
    error_message = "The alarm must watch the given metric"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.custom_step["queue_depth_high"].dimensions == tomap({ QueueName = "alpha-dev-jobs" })
    error_message = "The alarm must use the given dimensions"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.custom_step["queue_depth_high"].threshold == 100 && aws_cloudwatch_metric_alarm.custom_step["queue_depth_high"].evaluation_periods == 2 && aws_cloudwatch_metric_alarm.custom_step["queue_depth_high"].comparison_operator == "GreaterThanOrEqualToThreshold"
    error_message = "Threshold, evaluation periods and comparison must pass through"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.custom_step["queue_depth_high"].alarm_actions == toset([aws_appautoscaling_policy.custom_step["queue_depth_high"].arn])
    error_message = "The alarm action must be the policy ARN"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.custom_step["queue_depth_high"].metric_query) == 0
    error_message = "A metric type policy must not use metric_query"
  }

  assert {
    condition     = length(aws_appautoscaling_policy.cpu) == 0 && length(aws_appautoscaling_policy.step) == 0
    error_message = "custom must not create built-in policies next to the custom one"
  }
}

run "queries_step_policy_uses_metric_math" {
  command = plan

  variables {
    autoscaling = {
      min_capacity = 1
      max_capacity = 10
      policy       = "custom"
      step_policies = {
        backlog_per_task = {
          comparison_operator = "GreaterThanThreshold"
          threshold           = 20
          evaluation_periods  = 3
          queries = [
            {
              id = "visible"
              metric = {
                namespace   = "AWS/SQS"
                metric_name = "ApproximateNumberOfMessagesVisible"
                dimensions  = { QueueName = "alpha-dev-jobs" }
                stat        = "Average"
              }
              return_data = false
            },
            {
              id = "tasks"
              metric = {
                namespace   = "ECS/ContainerInsights"
                metric_name = "RunningTaskCount"
                dimensions  = { ClusterName = "alpha-dev", ServiceName = "alpha-api" }
              }
              return_data = false
            },
            {
              id          = "ratio"
              expression  = "visible / tasks"
              label       = "Backlog per task"
              return_data = true
            },
          ]
          adjustments = [{ lower = 0, change = 2 }]
        }
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.custom_step["backlog_per_task"].metric_query) == 3
    error_message = "Each query must become a metric_query"
  }

  assert {
    condition     = one([for q in aws_cloudwatch_metric_alarm.custom_step["backlog_per_task"].metric_query : q.expression if q.id == "ratio"]) == "visible / tasks"
    error_message = "The expression query must be passed through"
  }

  assert {
    condition     = one([for q in aws_cloudwatch_metric_alarm.custom_step["backlog_per_task"].metric_query : q.return_data if q.id == "ratio"]) == true
    error_message = "Exactly the expression must return data"
  }

  assert {
    condition     = one(one([for q in aws_cloudwatch_metric_alarm.custom_step["backlog_per_task"].metric_query : q.metric if q.id == "visible"])).metric_name == "ApproximateNumberOfMessagesVisible"
    error_message = "Metric queries must carry their metric"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.custom_step["backlog_per_task"].metric_name == null
    error_message = "A queries policy must not set the alarm metric_name"
  }
}

run "metric_and_queries_together_rejected" {
  command = plan

  variables {
    autoscaling = {
      min_capacity = 1
      max_capacity = 10
      policy       = "custom"
      step_policies = {
        both = {
          comparison_operator = "GreaterThanThreshold"
          threshold           = 20
          evaluation_periods  = 1
          metric              = { namespace = "AWS/SQS", metric_name = "M" }
          queries             = [{ id = "q", expression = "1", return_data = true }]
          adjustments         = [{ lower = 0, change = 1 }]
        }
      }
    }
  }

  expect_failures = [var.autoscaling]
}

run "neither_metric_nor_queries_rejected" {
  command = plan

  variables {
    autoscaling = {
      min_capacity = 1
      max_capacity = 10
      policy       = "custom"
      step_policies = {
        none = {
          comparison_operator = "GreaterThanThreshold"
          threshold           = 20
          evaluation_periods  = 1
          adjustments         = [{ lower = 0, change = 1 }]
        }
      }
    }
  }

  expect_failures = [var.autoscaling]
}

run "step_policy_key_must_be_snake_case" {
  command = plan

  variables {
    autoscaling = {
      min_capacity = 1
      max_capacity = 10
      policy       = "custom"
      step_policies = {
        QueueDepth = {
          comparison_operator = "GreaterThanThreshold"
          threshold           = 20
          evaluation_periods  = 1
          metric              = { namespace = "AWS/SQS", metric_name = "M" }
          adjustments         = [{ lower = 0, change = 1 }]
        }
      }
    }
  }

  expect_failures = [var.autoscaling]
}

run "custom_step_policies_work_next_to_builtin_step" {
  command = plan

  variables {
    autoscaling = {
      min_capacity = 1
      max_capacity = 10
      policy       = "step"
      step_policies = {
        queue_depth_high = {
          comparison_operator = "GreaterThanOrEqualToThreshold"
          threshold           = 100
          evaluation_periods  = 1
          metric              = { namespace = "AWS/SQS", metric_name = "M" }
          adjustments         = [{ lower = 0, change = 1 }]
        }
      }
    }
  }

  assert {
    condition     = length(aws_appautoscaling_policy.step) == 4 && length(aws_appautoscaling_policy.custom_step) == 1
    error_message = "Built-in and custom step policies must coexist without name clashes"
  }

  assert {
    condition     = !contains([for p in aws_appautoscaling_policy.step : p.name], aws_appautoscaling_policy.custom_step["queue_depth_high"].name)
    error_message = "Custom policy names must not clash with built-in ones"
  }
}

run "scheduled_action_created" {
  command = plan

  variables {
    autoscaling = {
      min_capacity = 1
      max_capacity = 10
      scheduled_actions = {
        business_hours = {
          schedule     = "cron(0 8 ? * MON-FRI *)"
          timezone     = "Asia/Taipei"
          min_capacity = 4
          max_capacity = 10
        }
        night = {
          schedule     = "cron(0 20 ? * MON-FRI *)"
          min_capacity = 1
          max_capacity = 2
        }
      }
    }
    desired_count = 1
  }

  assert {
    condition     = length(aws_appautoscaling_scheduled_action.this) == 2
    error_message = "One scheduled action per entry"
  }

  assert {
    condition     = aws_appautoscaling_scheduled_action.this["business_hours"].schedule == "cron(0 8 ? * MON-FRI *)" && aws_appautoscaling_scheduled_action.this["business_hours"].timezone == "Asia/Taipei"
    error_message = "Schedule and timezone must pass through"
  }

  assert {
    condition     = aws_appautoscaling_scheduled_action.this["night"].timezone == "UTC"
    error_message = "timezone must default to UTC"
  }

  assert {
    condition     = one(aws_appautoscaling_scheduled_action.this["business_hours"].scalable_target_action).min_capacity == "4" && one(aws_appautoscaling_scheduled_action.this["business_hours"].scalable_target_action).max_capacity == "10"
    error_message = "Capacity must pass through"
  }

  assert {
    condition     = aws_appautoscaling_scheduled_action.this["night"].name == "alpha-api-night"
    error_message = "Scheduled action name must be <name>-<key with _ replaced by ->"
  }

  assert {
    condition     = aws_appautoscaling_scheduled_action.this["night"].resource_id == aws_appautoscaling_target.this.resource_id
    error_message = "The scheduled action must target the service scalable target"
  }
}

run "scheduled_capacity_equal_to_max_accepted" {
  command = plan

  variables {
    autoscaling = {
      min_capacity = 1
      max_capacity = 6
      scheduled_actions = {
        peak = { schedule = "cron(0 8 ? * * *)", min_capacity = 6, max_capacity = 6 }
      }
    }
  }

  assert {
    condition     = length(aws_appautoscaling_scheduled_action.this) == 1
    error_message = "A scheduled capacity equal to max_capacity must be accepted"
  }
}

run "scheduled_max_above_autoscaling_max_rejected" {
  command = plan

  variables {
    autoscaling = {
      min_capacity = 1
      max_capacity = 6
      scheduled_actions = {
        peak = { schedule = "cron(0 8 ? * * *)", min_capacity = 2, max_capacity = 7 }
      }
    }
  }

  expect_failures = [var.autoscaling]
}

run "scheduled_min_above_autoscaling_max_rejected" {
  command = plan

  variables {
    autoscaling = {
      min_capacity = 1
      max_capacity = 6
      scheduled_actions = {
        peak = { schedule = "cron(0 8 ? * * *)", min_capacity = 7, max_capacity = 7 }
      }
    }
  }

  expect_failures = [var.autoscaling]
}

run "scheduled_min_above_scheduled_max_rejected" {
  command = plan

  variables {
    autoscaling = {
      min_capacity = 1
      max_capacity = 6
      scheduled_actions = {
        peak = { schedule = "cron(0 8 ? * * *)", min_capacity = 5, max_capacity = 4 }
      }
    }
  }

  expect_failures = [var.autoscaling]
}

run "unknown_policy_still_rejected" {
  command = plan

  variables {
    autoscaling = { min_capacity = 1, max_capacity = 3, policy = "predictive" }
  }

  expect_failures = [var.autoscaling]
}
