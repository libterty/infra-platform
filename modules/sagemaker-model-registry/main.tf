resource "aws_sagemaker_model_package_group" "this" {
  model_package_group_name        = var.name
  model_package_group_description = var.description

  tags = merge(var.tags, { Name = var.name })
}

locals {
  group_arn = aws_sagemaker_model_package_group.this.arn
  partition = split(":", local.group_arn)[1]

  # Account IDs are expanded to root ARNs so the stored policy matches what IAM normalises it to.
  read_principals = [for p in var.cross_account_read_principals :
    can(regex("^[0-9]{12}$", p)) ? "arn:${local.partition}:iam::${p}:root" : p
  ]
}

resource "aws_sagemaker_model_package_group_policy" "this" {
  count = length(var.cross_account_read_principals) > 0 ? 1 : 0

  model_package_group_name = aws_sagemaker_model_package_group.this.model_package_group_name

  resource_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ReadModelPackageGroup"
        Effect    = "Allow"
        Principal = { AWS = local.read_principals }
        Action    = ["sagemaker:DescribeModelPackageGroup"]
        Resource  = local.group_arn
      },
      {
        Sid       = "ReadModelPackages"
        Effect    = "Allow"
        Principal = { AWS = local.read_principals }
        Action    = ["sagemaker:CreateModel", "sagemaker:DescribeModelPackage", "sagemaker:ListModelPackages"]
        Resource  = "${replace(local.group_arn, ":model-package-group/", ":model-package/")}/*"
      },
    ]
  })
}
