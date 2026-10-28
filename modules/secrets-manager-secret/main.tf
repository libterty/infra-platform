# Container only: the value is written by a person or a rotation process, never by Terraform, so it stays out of
# tfvars, SSM and state.
resource "aws_secretsmanager_secret" "this" {
  name                    = var.name
  description             = var.description
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, { Name = var.name })
}

locals {
  # Resource "*" in a secret's resource policy means the secret the policy is attached to.
  policy_statements = [for s in var.policy_statements : merge(
    {
      Sid       = s.sid
      Effect    = s.effect
      Principal = { (s.principals.type) = s.principals.identifiers }
      Action    = s.actions
      Resource  = "*"
    },
    length(s.conditions) == 0 ? {} : {
      Condition = {
        for t in distinct([for c in s.conditions : c.test]) :
        t => { for c in s.conditions : c.variable => c.values if c.test == t }
      }
    }
  )]
}

resource "aws_secretsmanager_secret_policy" "this" {
  count = length(var.policy_statements) == 0 ? 0 : 1

  secret_arn = aws_secretsmanager_secret.this.arn
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.policy_statements
  })

  # Secrets Manager refuses a policy that grants broad access (for example to every principal of any account).
  block_public_policy = true
}

resource "aws_secretsmanager_secret_rotation" "this" {
  count = var.rotation == null ? 0 : 1

  secret_id           = aws_secretsmanager_secret.this.id
  rotation_lambda_arn = var.rotation.lambda_arn
  rotate_immediately  = var.rotation.rotate_immediately

  rotation_rules {
    automatically_after_days = var.rotation.automatically_after_days
    schedule_expression      = var.rotation.schedule_expression
    duration                 = var.rotation.duration
  }
}
