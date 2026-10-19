# The Proxy role is created by iam-base with a trust policy only. The permission to read the master secret is attached
# here, after the data stack created the secret. It is attached whether or not a Proxy is used, so turning the Proxy on
# later does not require another apply of this stack.
locals {
  database = jsondecode(module.in.strings["database"])

  # null when the database is disabled; nothing that uses it is created in that case.
  db_secret_arn = try(local.database.secret_arn, null)

  # kms:Decrypt is limited to the project key and to calls made through Secrets Manager.
  db_secret_statements = [
    {
      Sid      = "ReadDatabaseMasterSecret"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = local.db_secret_arn
    },
    {
      Sid       = "DecryptMasterSecret"
      Effect    = "Allow"
      Action    = ["kms:Decrypt"]
      Resource  = module.in.strings["kms_key_arn"]
      Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com" } }
    },
  ]
}

locals {
  proxy_secret_access = {
    role_arn = module.in.strings["role_rds_proxy_arn"]
    policies = {
      read-master-secret = jsonencode({ Version = "2012-10-17", Statement = local.db_secret_statements })
    }
  }
}

module "proxy_secret_access" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/iam-role-policy/aws"
  version  = "~> 0.1.0"
  for_each = local.database.enabled ? { proxy = true } : {}

  role_arn = local.proxy_secret_access.role_arn
  policies = local.proxy_secret_access.policies
}
