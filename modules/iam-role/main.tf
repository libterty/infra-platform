locals {
  federated = var.trust.federated

  # IRSA condition keys are prefixed with the issuer, i.e. the provider ARN without "arn:aws:iam::<account>:oidc-provider/".
  oidc_issuer = local.federated == null ? null : regex("^arn:aws:iam::[0-9]{12}:oidc-provider/(.+)$", local.federated.oidc_provider_arn)[0]

  # A plain string without tag_session keeps the 0.2.0 JSON; the two shapes differ in type, so pick one through JSON.
  service_action = jsondecode(var.trust.tag_session ? "[\"sts:AssumeRole\", \"sts:TagSession\"]" : "\"sts:AssumeRole\"")

  # Exactly one of the two lists is non-empty (enforced by the trust validation), so the policy has one statement.
  service_statements = local.federated == null ? [merge(
    {
      Effect    = "Allow"
      Action    = local.service_action
      Principal = { Service = sort(tolist(var.trust.service_principals)) }
    },
    length(local.trust_condition) == 0 ? {} : { Condition = local.trust_condition },
  )] : []

  federated_statements = [for f in local.federated == null ? [] : [local.federated] : {
    Effect    = "Allow"
    Action    = "sts:AssumeRoleWithWebIdentity"
    Principal = { Federated = f.oidc_provider_arn }
    Condition = {
      StringEquals = {
        "${local.oidc_issuer}:sub" = f.subject
        "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
      }
    }
  }]

  trust_condition = merge(
    var.trust.source_account == null ? {} : { StringEquals = { "aws:SourceAccount" = var.trust.source_account } },
    var.trust.source_arn == null ? {} : { ArnLike = { "aws:SourceArn" = var.trust.source_arn } },
  )
}

resource "aws_iam_role" "this" {
  name                 = var.name
  description          = var.description
  permissions_boundary = var.permissions_boundary

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = concat(local.service_statements, local.federated_statements)
  })

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_iam_role_policy" "this" {
  for_each = var.inline_policies

  name   = each.key
  role   = aws_iam_role.this.name
  policy = each.value
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = var.managed_policy_arns

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "this" {
  count = var.instance_profile_name == null ? 0 : 1

  name = var.instance_profile_name
  role = aws_iam_role.this.name

  tags = merge(var.tags, { Name = var.instance_profile_name })
}
