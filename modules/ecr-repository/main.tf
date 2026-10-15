resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = var.kms_key_arn == null ? "AES256" : "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = merge(var.tags, { Name = var.name })
}

# Rule 2 uses tagStatus "any": a "tagged" rule needs tag prefixes or patterns, which would couple the module to a tag scheme.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.lifecycle_rules.untagged_expire_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.lifecycle_rules.untagged_expire_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the latest ${var.lifecycle_rules.keep_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.lifecycle_rules.keep_count
        }
        action = { type = "expire" }
      },
    ]
  })
}
