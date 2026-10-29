resource "aws_backup_plan" "this" {
  region = var.region
  name   = var.name

  dynamic "rule" {
    for_each = var.rules
    content {
      rule_name                = rule.key
      target_vault_name        = var.vault_name
      schedule                 = rule.value.schedule
      start_window             = rule.value.start_window_minutes
      completion_window        = rule.value.completion_window_minutes
      enable_continuous_backup = rule.value.enable_continuous_backup

      dynamic "lifecycle" {
        for_each = rule.value.delete_after_days == null && rule.value.cold_storage_after_days == null ? [] : [rule.value]
        content {
          delete_after       = lifecycle.value.delete_after_days
          cold_storage_after = lifecycle.value.cold_storage_after_days
        }
      }

      dynamic "copy_action" {
        for_each = rule.value.copy_to == null ? [] : [rule.value.copy_to]
        content {
          destination_vault_arn = copy_action.value.vault_arn

          dynamic "lifecycle" {
            for_each = copy_action.value.delete_after_days == null ? [] : [copy_action.value.delete_after_days]
            content {
              delete_after = lifecycle.value
            }
          }
        }
      }
    }
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_backup_selection" "this" {
  region       = var.region
  name         = var.name
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = var.role_arn

  # Multiple selection_tag blocks are ORed: a resource matching any tag is backed up.
  dynamic "selection_tag" {
    for_each = var.selection_tags
    content {
      type  = "STRINGEQUALS"
      key   = selection_tag.key
      value = selection_tag.value
    }
  }
}
