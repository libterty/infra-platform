mock_provider "aws" {}

variables {
  zone_id = "Z0123456789ABCDEFGHIJ"
  records = {
    app = {
      name = "app.dev.example.com"
      type = "A"
      alias = {
        name    = "d111111abcdef8.cloudfront.net"
        zone_id = "Z2FDTNDATAQYW2"
      }
    }
    app_ipv6 = {
      name = "app.dev.example.com"
      type = "AAAA"
      alias = {
        name                   = "d111111abcdef8.cloudfront.net"
        zone_id                = "Z2FDTNDATAQYW2"
        evaluate_target_health = true
      }
    }
    verify = {
      name   = "dev.example.com"
      type   = "TXT"
      ttl    = 300
      values = ["v=spf1 -all", "site-verification=abc123"]
    }
    www = {
      name   = "www.dev.example.com"
      type   = "CNAME"
      ttl    = 60
      values = ["app.dev.example.com"]
    }
  }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "alias_txt_and_cname" {
  command = plan

  assert {
    condition     = length(aws_route53_record.this) == 4
    error_message = "One record per records entry"
  }

  assert {
    condition     = alltrue([for r in aws_route53_record.this : r.zone_id == "Z0123456789ABCDEFGHIJ"])
    error_message = "Every record must be created in zone_id"
  }

  assert {
    condition     = alltrue([for r in aws_route53_record.this : r.allow_overwrite == false])
    error_message = "allow_overwrite must be fixed to false so an existing record is never taken over"
  }

  assert {
    condition = (
      aws_route53_record.this["app"].type == "A" &&
      one(aws_route53_record.this["app"].alias).name == "d111111abcdef8.cloudfront.net" &&
      one(aws_route53_record.this["app"].alias).zone_id == "Z2FDTNDATAQYW2" &&
      one(aws_route53_record.this["app"].alias).evaluate_target_health == false
    )
    error_message = "The A alias must point at the given target with evaluate_target_health defaulting to false"
  }

  assert {
    condition     = aws_route53_record.this["app"].ttl == null && aws_route53_record.this["app"].records == null
    error_message = "An alias record must not set ttl or records"
  }

  assert {
    condition     = one(aws_route53_record.this["app_ipv6"].alias).evaluate_target_health == true
    error_message = "evaluate_target_health must be passed through"
  }

  assert {
    condition = (
      aws_route53_record.this["verify"].type == "TXT" &&
      aws_route53_record.this["verify"].ttl == 300 &&
      aws_route53_record.this["verify"].records == toset(["v=spf1 -all", "site-verification=abc123"]) &&
      length(aws_route53_record.this["verify"].alias) == 0
    )
    error_message = "The TXT record must carry every value and the ttl, without alias"
  }

  assert {
    condition = (
      aws_route53_record.this["www"].name == "www.dev.example.com" &&
      aws_route53_record.this["www"].type == "CNAME" &&
      aws_route53_record.this["www"].records == toset(["app.dev.example.com"])
    )
    error_message = "The CNAME record must be passed through"
  }
}

run "fqdns_output" {
  override_resource {
    target = aws_route53_record.this["www"]
    values = {
      fqdn = "www.dev.example.com"
    }
  }

  assert {
    condition     = toset(keys(output.fqdns)) == toset(["app", "app_ipv6", "verify", "www"])
    error_message = "fqdns must be keyed by the records keys"
  }

  assert {
    condition     = output.fqdns["www"] == "www.dev.example.com"
    error_message = "fqdns must map each key to the record FQDN"
  }
}

run "ttl_boundaries_accepted" {
  command = plan

  variables {
    records = {
      low = {
        name   = "low.dev.example.com"
        type   = "A"
        ttl    = 60
        values = ["192.0.2.10"]
      }
      high = {
        name   = "high.dev.example.com"
        type   = "MX"
        ttl    = 172800
        values = ["10 mail.example.com"]
      }
    }
  }

  assert {
    condition     = aws_route53_record.this["low"].ttl == 60 && aws_route53_record.this["high"].ttl == 172800
    error_message = "ttl 60 and 172800 must be accepted"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "alias_on_txt_rejected" {
  command = plan

  variables {
    records = {
      bad = {
        name  = "dev.example.com"
        type  = "TXT"
        alias = { name = "d111111abcdef8.cloudfront.net", zone_id = "Z2FDTNDATAQYW2" }
      }
    }
  }

  expect_failures = [var.records]
}

run "cname_with_two_values_rejected" {
  command = plan

  variables {
    records = {
      bad = {
        name   = "www.dev.example.com"
        type   = "CNAME"
        ttl    = 300
        values = ["a.example.com", "b.example.com"]
      }
    }
  }

  expect_failures = [var.records]
}

run "ttl_zero_rejected" {
  command = plan

  variables {
    records = {
      bad = {
        name   = "api.dev.example.com"
        type   = "A"
        ttl    = 0
        values = ["192.0.2.10"]
      }
    }
  }

  expect_failures = [var.records]
}

run "ttl_above_max_rejected" {
  command = plan

  variables {
    records = {
      bad = {
        name   = "api.dev.example.com"
        type   = "A"
        ttl    = 172801
        values = ["192.0.2.10"]
      }
    }
  }

  expect_failures = [var.records]
}

run "missing_ttl_rejected" {
  command = plan

  variables {
    records = {
      bad = {
        name   = "api.dev.example.com"
        type   = "A"
        values = ["192.0.2.10"]
      }
    }
  }

  expect_failures = [var.records]
}

run "neither_values_nor_alias_rejected" {
  command = plan

  variables {
    records = {
      bad = {
        name = "api.dev.example.com"
        type = "A"
        ttl  = 300
      }
    }
  }

  expect_failures = [var.records]
}

run "empty_values_rejected" {
  command = plan

  variables {
    records = {
      bad = {
        name   = "api.dev.example.com"
        type   = "A"
        ttl    = 300
        values = []
      }
    }
  }

  expect_failures = [var.records]
}

run "values_and_alias_together_rejected" {
  command = plan

  variables {
    records = {
      bad = {
        name   = "api.dev.example.com"
        type   = "A"
        values = ["192.0.2.10"]
        alias  = { name = "d111111abcdef8.cloudfront.net", zone_id = "Z2FDTNDATAQYW2" }
      }
    }
  }

  expect_failures = [var.records]
}

run "alias_with_ttl_rejected" {
  command = plan

  variables {
    records = {
      bad = {
        name  = "api.dev.example.com"
        type  = "A"
        ttl   = 300
        alias = { name = "d111111abcdef8.cloudfront.net", zone_id = "Z2FDTNDATAQYW2" }
      }
    }
  }

  expect_failures = [var.records]
}

run "unsupported_type_rejected" {
  command = plan

  variables {
    records = {
      bad = {
        name   = "api.dev.example.com"
        type   = "PTR"
        ttl    = 300
        values = ["host.example.com"]
      }
    }
  }

  expect_failures = [var.records]
}

run "invalid_zone_id_rejected" {
  command = plan

  variables {
    zone_id = "dev.example.com"
  }

  expect_failures = [var.zone_id]
}
