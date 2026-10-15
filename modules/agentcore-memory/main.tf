resource "aws_bedrockagentcore_memory" "this" {
  name                  = var.name
  description           = var.description
  event_expiry_duration = var.event_expiry_days
  encryption_key_arn    = var.kms_key_arn

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_bedrockagentcore_memory_strategy" "this" {
  for_each = var.strategies

  memory_id           = aws_bedrockagentcore_memory.this.id
  name                = each.key
  type                = each.value.type
  namespace_templates = each.value.namespaces
  description         = each.value.description
}
