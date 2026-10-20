terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

module "alarms" {
  source = "../.."

  name_prefix    = "alpha-dev-api"
  sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]

  alarms = {
    # Single metric.
    queue_depth_high = {
      description         = "Messages are piling up in the queue. Check whether the consumer is running first."
      comparison_operator = "GreaterThanThreshold"
      threshold           = 100
      evaluation_periods  = 3
      datapoints_to_alarm = 2
      metric = {
        namespace   = "AWS/SQS"
        metric_name = "ApproximateNumberOfMessagesVisible"
        dimensions  = { QueueName = "alpha-dev-jobs" }
        statistic   = "Maximum"
      }
    }

    # Metric math: 5xx per request, in percent.
    error_rate_high = {
      description         = "More than 5 percent of requests fail with 5xx. Check the application logs first."
      comparison_operator = "GreaterThanThreshold"
      threshold           = 5
      evaluation_periods  = 2
      queries = [
        {
          id = "errors"
          metric = {
            namespace   = "AWS/ApplicationELB"
            metric_name = "HTTPCode_Target_5XX_Count"
            dimensions  = { LoadBalancer = "app/alpha-dev/0123456789abcdef" }
            statistic   = "Sum"
          }
        },
        {
          id = "requests"
          metric = {
            namespace   = "AWS/ApplicationELB"
            metric_name = "RequestCount"
            dimensions  = { LoadBalancer = "app/alpha-dev/0123456789abcdef" }
            statistic   = "Sum"
          }
        },
        {
          id          = "rate"
          expression  = "100 * errors / requests"
          label       = "5xx percent"
          return_data = true
        },
      ]
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "alarm_names" {
  value = module.alarms.alarm_names
}
