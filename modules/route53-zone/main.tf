resource "aws_route53_zone" "this" {
  name          = var.name
  comment       = var.comment
  force_destroy = var.force_destroy

  dynamic "vpc" {
    for_each = var.private_vpc_ids
    content {
      vpc_id = vpc.value
    }
  }

  tags = merge(var.tags, { Name = var.name })
}
