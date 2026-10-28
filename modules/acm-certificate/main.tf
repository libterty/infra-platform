locals {
  # The apex and its wildcard share one validation record, so both fold into the apex key.
  # Keys come from the inputs so they are known at plan time.
  validation_keys = toset([for n in concat([var.domain_name], var.subject_alternative_names) : trimprefix(n, "*.")])

  validation_options = {
    for o in aws_acm_certificate.this.domain_validation_options : trimprefix(o.domain_name, "*.") => o...
  }
}

resource "aws_acm_certificate" "this" {
  region                    = var.region
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"
  key_algorithm             = var.key_algorithm

  tags = var.tags

  # Changing names replaces the certificate; the new one must exist before the old one,
  # which is still attached to a load balancer or distribution, can be deleted.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = local.validation_keys

  zone_id = var.zone_id
  name    = local.validation_options[each.key][0].resource_record_name
  type    = local.validation_options[each.key][0].resource_record_type
  records = [local.validation_options[each.key][0].resource_record_value]
  ttl     = 60

  # ACM gives the same record to every certificate in the account that covers this name,
  # for example a regional and a us-east-1 certificate for the same host.
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  region                  = var.region
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]

  timeouts {
    create = var.validation_timeout
  }
}
