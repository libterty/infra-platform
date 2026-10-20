locals {
  # Fixed slots, so adding or removing an optional rule never renumbers the others.
  # Slot 20 is intentionally unused: the allowlist is a scope-down of the rate rule, not an allow rule.
  priority_kill_switch = 10
  priority_rate_limit  = 30
  priority_managed     = 100
  priority_body_size   = 1000

  has_allowlist = var.rate_limit != null && length(var.rate_limit.allowlist_cidrs) > 0

  managed_groups = {
    for i, g in var.managed_rule_groups : "${g.vendor}-${g.name}" => merge(g, { priority = local.priority_managed + i })
  }

  has_kill_switch_body = var.kill_switch != null && try(var.kill_switch.response_json, null) != null

  # authorization and cookie are always redacted; the caller can only add headers.
  redacted_headers = var.logging == null ? toset([]) : toset(concat(["authorization", "cookie"], [for h in var.logging.redacted_headers : lower(h)]))

  log_group_name = "aws-waf-logs-${var.name}"
}

resource "aws_wafv2_ip_set" "allowlist" {
  count = local.has_allowlist ? 1 : 0

  name               = "${var.name}-allowlist"
  description        = "Source IPs exempt from the rate limit of ${var.name}"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.rate_limit.allowlist_cidrs

  tags = merge(var.tags, { Name = "${var.name}-allowlist" })
}

resource "aws_wafv2_web_acl" "this" {
  name        = var.name
  description = "Web ACL ${var.name}"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  dynamic "custom_response_body" {
    for_each = local.has_kill_switch_body ? [1] : []
    content {
      key          = "kill-switch"
      content      = var.kill_switch.response_json
      content_type = "APPLICATION_JSON"
    }
  }

  dynamic "rule" {
    for_each = var.kill_switch == null ? [] : [var.kill_switch]
    content {
      name     = "kill-switch"
      priority = local.priority_kill_switch

      action {
        dynamic "count" {
          for_each = rule.value.action == "count" ? [1] : []
          content {}
        }

        dynamic "block" {
          for_each = rule.value.action == "block" ? [1] : []
          content {
            dynamic "custom_response" {
              for_each = rule.value.response_json == null ? [] : [1]
              content {
                response_code            = 503
                custom_response_body_key = "kill-switch"
              }
            }
          }
        }
      }

      # A URI path is never shorter than 0 bytes, so this matches every request.
      statement {
        size_constraint_statement {
          comparison_operator = "GE"
          size                = 0

          field_to_match {
            uri_path {}
          }

          text_transformation {
            priority = 0
            type     = "NONE"
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "kill-switch"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.rate_limit == null ? [] : [var.rate_limit]
    content {
      name     = "rate-limit"
      priority = local.priority_rate_limit

      action {
        block {}
      }

      statement {
        rate_based_statement {
          limit              = rule.value.limit
          aggregate_key_type = "IP"

          dynamic "scope_down_statement" {
            for_each = local.has_allowlist ? [1] : []
            content {
              not_statement {
                statement {
                  ip_set_reference_statement {
                    arn = aws_wafv2_ip_set.allowlist[0].arn
                  }
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "rate-limit"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = local.managed_groups
    content {
      name     = rule.key
      priority = rule.value.priority

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = rule.value.vendor

          dynamic "rule_action_override" {
            for_each = toset(rule.value.count_overrides)
            content {
              name = rule_action_override.value

              action_to_use {
                count {}
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.key
        sampled_requests_enabled   = true
      }
    }
  }

  # The managed rule's own body limit is switched to count when paths are exempt, so the same 8 KB limit is
  # enforced here for every path except the exempt prefixes.
  dynamic "rule" {
    for_each = length(var.body_size_exempt_path_prefixes) > 0 ? [1] : []
    content {
      name     = "body-size-limit"
      priority = local.priority_body_size

      action {
        block {}
      }

      statement {
        and_statement {
          statement {
            size_constraint_statement {
              comparison_operator = "GT"
              size                = 8192

              field_to_match {
                body {
                  oversize_handling = "MATCH"
                }
              }

              text_transformation {
                priority = 0
                type     = "NONE"
              }
            }
          }

          dynamic "statement" {
            for_each = toset(var.body_size_exempt_path_prefixes)
            content {
              not_statement {
                statement {
                  byte_match_statement {
                    positional_constraint = "STARTS_WITH"
                    search_string         = statement.value

                    field_to_match {
                      uri_path {}
                    }

                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "body-size-limit"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, { Name = var.name })
}

# WAF only delivers to log groups whose name starts with aws-waf-logs-.
resource "aws_cloudwatch_log_group" "waf" {
  count = var.logging == null ? 0 : 1

  name              = local.log_group_name
  retention_in_days = var.logging.retention_days
  kms_key_id        = var.logging.kms_key_arn

  tags = merge(var.tags, { Name = local.log_group_name })
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count = var.logging == null ? 0 : 1

  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]

  dynamic "redacted_fields" {
    for_each = local.redacted_headers
    content {
      single_header {
        name = redacted_fields.value
      }
    }
  }
}
