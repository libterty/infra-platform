mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
}

# The SSM values are only read here, so fixed ones stand in for them (the mock would return random text).
override_module {
  target = module.in
  outputs = {
    strings = {
      zone_id   = "Z0123456789ABCDEFGHIJ"
      zone_name = "dev.example.com"
    }
  }
}

run "reads_the_zone_from_dns" {
  command = plan

  assert {
    condition     = local.ssm_input_strings == { zone_id = "dns/zone_id", zone_name = "dns/zone_name" }
    error_message = "certificate reads the zone ID and name that dns publishes in tree A"
  }

  assert {
    condition     = local.zone_id == "Z0123456789ABCDEFGHIJ" && local.zone_name == "dev.example.com"
    error_message = "The validation records go into the zone read from SSM"
  }
}

run "alb_certificate_covers_api_and_origin_api" {
  command = plan

  assert {
    condition     = local.alb_certificate.domain_name == "api.dev.example.com"
    error_message = "CloudFront forwards the viewer Host, so the ALB certificate must cover api.<zone>"
  }

  assert {
    condition     = local.alb_certificate.subject_alternative_names == ["origin-api.dev.example.com"]
    error_message = "CloudFront connects to origin-api.<zone>, so it is the one SAN of the ALB certificate"
  }

  assert {
    condition     = module.alb_certificate.domain_name == "api.dev.example.com"
    error_message = "The ALB certificate module gets the api name"
  }
}

run "cloudfront_certificate_is_api_in_us_east_1" {
  command = plan

  assert {
    condition     = local.cloudfront_certificate == { domain_name = "api.dev.example.com", region = "us-east-1" }
    error_message = "CloudFront only accepts a us-east-1 certificate, and viewers use api.<zone>"
  }

  assert {
    condition     = module.cloudfront_certificate.domain_name == "api.dev.example.com"
    error_message = "The CloudFront certificate module gets the api name"
  }
}

run "publishes_both_certificate_arns" {
  command = plan

  override_module {
    target = module.alb_certificate
    outputs = {
      certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/00000000-0000-0000-0000-000000000001"
      domain_name     = "api.dev.example.com"
    }
  }

  override_module {
    target = module.cloudfront_certificate
    outputs = {
      certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000002"
      domain_name     = "api.dev.example.com"
    }
  }

  assert {
    condition = local.published_strings == {
      alb_certificate_arn        = "arn:aws:acm:ap-northeast-1:111111111111:certificate/00000000-0000-0000-0000-000000000001"
      cloudfront_certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000002"
    }
    error_message = "alb_certificate_arn is the regional certificate, cloudfront_certificate_arn the us-east-1 one"
  }

  assert {
    condition = module.ssm_publish.names == {
      alb_certificate_arn        = "/example/dev/certificate/alb_certificate_arn"
      cloudfront_certificate_arn = "/example/dev/certificate/cloudfront_certificate_arn"
    }
    error_message = "ssm-publish must write exactly the two certificate keys under the certificate path"
  }
}
