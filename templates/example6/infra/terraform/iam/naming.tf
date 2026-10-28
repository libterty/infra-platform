# Naming rule shared with the api stack (applied later): the API Lambda is named <name_prefix>-api, and lambda-function
# creates its log group /aws/lambda/<name>. The log group does not exist when iam is applied, so its ARN is built
# from the name; the api stack must use exactly the same function name.
locals {
  api_function_name = "${local.name_prefix}-api"
  api_log_group_arn = "arn:aws:logs:${var.aws_region}:${var.expected_account_id}:log-group:/aws/lambda/${local.api_function_name}"
}
