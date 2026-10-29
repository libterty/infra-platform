resource "aws_accessanalyzer_analyzer" "this" {
  analyzer_name = var.name
  type          = var.type
  region        = var.region

  dynamic "configuration" {
    for_each = var.unused_access_age_days == null ? [] : [var.unused_access_age_days]
    content {
      unused_access {
        unused_access_age = configuration.value
      }
    }
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_accessanalyzer_archive_rule" "this" {
  for_each = var.archive_rules

  analyzer_name = aws_accessanalyzer_analyzer.this.analyzer_name
  rule_name     = each.key
  region        = var.region

  dynamic "filter" {
    for_each = each.value
    content {
      criteria = filter.value.criteria
      eq       = filter.value.eq
      neq      = filter.value.neq
      contains = filter.value.contains
      exists   = filter.value.exists == null ? null : tostring(filter.value.exists)
    }
  }
}
