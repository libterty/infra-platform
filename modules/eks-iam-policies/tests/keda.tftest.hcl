mock_provider "aws" {}

variables {
  cluster_name = "alpha-dev"
  region       = "ap-northeast-1"
  account_id   = "111111111111"
}

run "cloudwatch_get_metric_data_only" {
  command = plan

  assert {
    condition = jsondecode(output.keda_cloudwatch_policy_json) == jsondecode(jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["cloudwatch:GetMetricData"]
        Resource = "*"
      }]
    }))
    error_message = "KEDA policy must be exactly cloudwatch:GetMetricData on *"
  }
}

run "output_is_compact" {
  command = plan

  assert {
    condition     = !can(regex("\\s", output.keda_cloudwatch_policy_json))
    error_message = "Output must contain no whitespace"
  }
}
