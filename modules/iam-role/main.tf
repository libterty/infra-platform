resource "aws_iam_role" "this" {
  name                 = var.name
  description          = var.description
  permissions_boundary = var.permissions_boundary

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [merge(
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = sort(tolist(var.trust.service_principals)) }
      },
      var.trust.source_account == null ? {} : {
        Condition = { StringEquals = { "aws:SourceAccount" = var.trust.source_account } }
      },
    )]
  })

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_iam_role_policy" "this" {
  for_each = var.inline_policies

  name   = each.key
  role   = aws_iam_role.this.name
  policy = each.value
}
