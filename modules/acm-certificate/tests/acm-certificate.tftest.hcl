mock_provider "aws" {}

variables {
  domain_name               = "dev.example.com"
  subject_alternative_names = ["*.dev.example.com"]
  zone_id                   = "Z0123456789ABCDEFGHIJ"
}

# ---- positive -------------------------------------------------------------------------------------------------

run "apex_and_wildcard_plan" {
  command = plan

  assert {
    condition     = aws_acm_certificate.this.domain_name == "dev.example.com"
    error_message = "domain_name must be passed through"
  }

  assert {
    condition     = aws_acm_certificate.this.subject_alternative_names == toset(["*.dev.example.com"])
    error_message = "subject_alternative_names must be passed through"
  }

  assert {
    condition     = aws_acm_certificate.this.validation_method == "DNS"
    error_message = "The certificate must use DNS validation"
  }

  assert {
    condition     = aws_acm_certificate.this.key_algorithm == "RSA_2048"
    error_message = "key_algorithm must default to RSA_2048"
  }

  assert {
    condition     = keys(aws_route53_record.validation) == ["dev.example.com"]
    error_message = "The apex and its wildcard share one validation record"
  }

  assert {
    condition     = aws_route53_record.validation["dev.example.com"].zone_id == "Z0123456789ABCDEFGHIJ" && aws_route53_record.validation["dev.example.com"].ttl == 60
    error_message = "Validation records go into zone_id with a 60 second ttl"
  }

  assert {
    condition     = aws_route53_record.validation["dev.example.com"].allow_overwrite == true
    error_message = "Validation records must allow overwrite: certificates for the same names share the record"
  }

  assert {
    condition     = aws_acm_certificate_validation.this.timeouts.create == "45m"
    error_message = "validation_timeout must default to 45m"
  }
}

run "cloudfront_certificate_in_us_east_1" {
  command = plan

  variables {
    domain_name               = "app.dev.example.com"
    subject_alternative_names = ["api.dev.example.com", "*.app.dev.example.com"]
    region                    = "us-east-1"
    key_algorithm             = "EC_prime256v1"
    validation_timeout        = "1h30m"
    tags                      = { Project = "alpha" }
  }

  assert {
    condition     = aws_acm_certificate.this.region == "us-east-1"
    error_message = "region must be set on the certificate"
  }

  assert {
    condition     = aws_acm_certificate_validation.this.region == "us-east-1"
    error_message = "region must be set on the validation resource too"
  }

  assert {
    condition     = toset(keys(aws_route53_record.validation)) == toset(["app.dev.example.com", "api.dev.example.com"])
    error_message = "One validation record per distinct name, with the wildcard folded into its base name"
  }

  assert {
    condition     = aws_acm_certificate.this.key_algorithm == "EC_prime256v1"
    error_message = "key_algorithm must be passed through"
  }

  assert {
    condition     = aws_acm_certificate_validation.this.timeouts.create == "1h30m"
    error_message = "validation_timeout must be passed through"
  }

  assert {
    condition     = aws_acm_certificate.this.tags["Project"] == "alpha"
    error_message = "tags must be passed through"
  }
}

run "ten_names_accepted" {
  command = plan

  variables {
    subject_alternative_names = [for i in range(9) : "s${i}.dev.example.com"]
  }

  assert {
    condition     = length(aws_route53_record.validation) == 10
    error_message = "domain_name plus 9 SANs must be accepted"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "eleven_names_rejected" {
  command = plan

  variables {
    subject_alternative_names = [for i in range(10) : "s${i}.dev.example.com"]
  }

  expect_failures = [var.subject_alternative_names]
}

run "wildcard_not_leftmost_in_san_rejected" {
  command = plan

  variables {
    subject_alternative_names = ["api.*.example.com"]
  }

  expect_failures = [var.subject_alternative_names]
}

run "wildcard_not_leftmost_in_domain_name_rejected" {
  command = plan

  variables {
    domain_name = "dev.*.example.com"
  }

  expect_failures = [var.domain_name]
}

run "partial_wildcard_label_rejected" {
  command = plan

  variables {
    domain_name = "api*.dev.example.com"
  }

  expect_failures = [var.domain_name]
}

run "invalid_domain_name_rejected" {
  command = plan

  variables {
    domain_name = "dev.example.com."
  }

  expect_failures = [var.domain_name]
}

run "invalid_san_rejected" {
  command = plan

  variables {
    subject_alternative_names = ["bad_name!.example.com"]
  }

  expect_failures = [var.subject_alternative_names]
}

run "invalid_region_rejected" {
  command = plan

  variables {
    region = "us_east_1"
  }

  expect_failures = [var.region]
}

run "unsupported_key_algorithm_rejected" {
  command = plan

  variables {
    key_algorithm = "RSA_1024"
  }

  expect_failures = [var.key_algorithm]
}

run "invalid_validation_timeout_rejected" {
  command = plan

  variables {
    validation_timeout = "45 minutes"
  }

  expect_failures = [var.validation_timeout]
}

run "invalid_zone_id_rejected" {
  command = plan

  variables {
    zone_id = "dev.example.com"
  }

  expect_failures = [var.zone_id]
}

# ---- mock apply (last, so its state does not leak into the plan runs above) -------------------------------

# Mock apply with ACM's answer for apex plus wildcard: both names get the same record.
run "apex_and_wildcard_apply_dedupes_validation_record" {
  override_resource {
    target = aws_acm_certificate.this
    values = {
      arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/1234abcd-12ab-34cd-56ef-1234567890ab"
      domain_validation_options = [
        {
          domain_name           = "dev.example.com"
          resource_record_name  = "_abc123.dev.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_def456.acm-validations.aws."
        },
        {
          domain_name           = "*.dev.example.com"
          resource_record_name  = "_abc123.dev.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_def456.acm-validations.aws."
        },
      ]
    }
  }

  override_resource {
    target = aws_route53_record.validation["dev.example.com"]
    values = {
      fqdn = "_abc123.dev.example.com"
    }
  }

  assert {
    condition     = length(aws_route53_record.validation) == 1
    error_message = "Apex plus wildcard must create exactly one validation record"
  }

  assert {
    condition = (
      aws_route53_record.validation["dev.example.com"].name == "_abc123.dev.example.com." &&
      aws_route53_record.validation["dev.example.com"].type == "CNAME" &&
      aws_route53_record.validation["dev.example.com"].records == toset(["_def456.acm-validations.aws."])
    )
    error_message = "The validation record must carry the name, type and value ACM asked for"
  }

  assert {
    condition     = aws_acm_certificate_validation.this.certificate_arn == "arn:aws:acm:ap-northeast-1:111111111111:certificate/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The validation must wait for this certificate"
  }

  assert {
    condition     = aws_acm_certificate_validation.this.validation_record_fqdns == toset(["_abc123.dev.example.com"])
    error_message = "The validation must wait for the created validation record"
  }

  assert {
    condition     = output.certificate_arn == "arn:aws:acm:ap-northeast-1:111111111111:certificate/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "certificate_arn output must be the validated certificate ARN"
  }

  assert {
    condition     = output.domain_name == "dev.example.com"
    error_message = "domain_name output must be the certificate domain name"
  }
}
