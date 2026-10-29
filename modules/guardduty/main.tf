resource "aws_guardduty_detector" "this" {
  region                       = var.region
  enable                       = true
  finding_publishing_frequency = var.finding_publishing_frequency

  tags = var.tags
}

# Features are managed with detector_feature; the detector's datasources block is the deprecated API.
resource "aws_guardduty_detector_feature" "this" {
  for_each = var.features

  region      = var.region
  detector_id = aws_guardduty_detector.this.id
  name        = each.key
  status      = each.value.status

  dynamic "additional_configuration" {
    for_each = each.value.additional_configuration
    content {
      name   = additional_configuration.key
      status = additional_configuration.value
    }
  }
}

resource "aws_guardduty_organization_configuration" "this" {
  count = var.organization == null ? 0 : 1

  region                           = var.region
  detector_id                      = aws_guardduty_detector.this.id
  auto_enable_organization_members = var.organization.auto_enable
}

resource "aws_guardduty_organization_configuration_feature" "this" {
  for_each = var.organization == null ? {} : var.organization.features

  region      = var.region
  detector_id = aws_guardduty_detector.this.id
  name        = each.key
  auto_enable = each.value.auto_enable

  dynamic "additional_configuration" {
    for_each = each.value.additional_configuration
    content {
      name        = additional_configuration.key
      auto_enable = additional_configuration.value
    }
  }

  depends_on = [aws_guardduty_organization_configuration.this]
}
