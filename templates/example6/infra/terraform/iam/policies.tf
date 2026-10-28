# Permissions of the API Lambda (design section 4: only this table and these secrets). Every Resource comes from a key
# that foundation or data publishes, or from the naming rule in naming.tf. The action lists follow the AWS service
# documentation and are not yet verified against a real account.
locals {
  table_arn   = module.in.strings["table_arn"]
  kms_key_arn = module.in.strings["kms_key_arn"]

  api_statement_list = [
    {
      Sid    = "ReadWriteTable"
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem", "dynamodb:BatchGetItem", "dynamodb:Query", "dynamodb:Scan", "dynamodb:PutItem", "dynamodb:UpdateItem",
        "dynamodb:DeleteItem", "dynamodb:BatchWriteItem", "dynamodb:ConditionCheckItem", "dynamodb:DescribeTable",
      ]
      Resource = [local.table_arn, "${local.table_arn}/index/*"]
    },
    {
      # Full ARNs from SSM: origin-verify ends like the random ARN suffix, so a name-based pattern would be ambiguous.
      Sid      = "ReadSecrets"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [module.in.strings["api_secret_arn"], module.in.strings["origin_verify_secret_arn"]]
    },
    {
      # The table and both secrets are encrypted with the shared key.
      Sid      = "DecryptWithSharedKey"
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = [local.kms_key_arn]
    },
    {
      # lambda-function creates the log group, so the role only creates streams and writes events in it.
      Sid      = "WriteOwnLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = ["${local.api_log_group_arn}:*"]
    },
  ]

  # Keyed by Sid so the tests can address one statement; the policy document lists them in Sid order.
  api_statements = { for s in local.api_statement_list : s.Sid => s }

  api_policies = {
    permissions = jsonencode({ Version = "2012-10-17", Statement = values(local.api_statements) })
  }
}

module "api_policy" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/iam-role-policy/aws"
  version = "~> 0.1.1"

  role_arn = module.api_role.arn
  policies = local.api_policies
}
