mock_provider "aws" {}

variables {
  name = "dev.example.com"
}

# ---- positive -------------------------------------------------------------------------------------------------

run "public_zone" {
  command = plan

  assert {
    condition     = aws_route53_zone.this.name == "dev.example.com"
    error_message = "name must be passed through"
  }

  assert {
    condition     = length(aws_route53_zone.this.vpc) == 0
    error_message = "A zone without private_vpc_ids must be public: no vpc block"
  }

  assert {
    condition     = aws_route53_zone.this.force_destroy == false
    error_message = "force_destroy must default to false"
  }

  assert {
    condition     = aws_route53_zone.this.tags["Name"] == "dev.example.com"
    error_message = "Name tag must be the zone name"
  }
}

run "public_zone_outputs" {
  override_resource {
    target = aws_route53_zone.this
    values = {
      zone_id      = "Z0123456789ABCDEFGHIJ"
      arn          = "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
      name_servers = ["ns-1.awsdns-01.org", "ns-2.awsdns-02.co.uk"]
    }
  }

  assert {
    condition     = output.zone_id == "Z0123456789ABCDEFGHIJ"
    error_message = "zone_id output must be the zone ID"
  }

  assert {
    condition     = output.arn == "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
    error_message = "arn output must be the zone ARN"
  }

  assert {
    condition     = output.name == "dev.example.com"
    error_message = "name output must be the zone name"
  }

  assert {
    condition     = output.name_servers == tolist(["ns-1.awsdns-01.org", "ns-2.awsdns-02.co.uk"])
    error_message = "name_servers output must list the delegation name servers of a public zone"
  }
}

run "private_zone" {
  variables {
    name            = "internal.example.com"
    comment         = "dev private zone"
    private_vpc_ids = ["vpc-0123456789abcdef0", "vpc-0fedcba9876543210"]
    force_destroy   = true
    tags            = { Project = "alpha" }
  }

  override_resource {
    target = aws_route53_zone.this
    values = {
      name_servers = ["ns-1.awsdns-01.org"]
    }
  }

  assert {
    condition     = toset([for v in aws_route53_zone.this.vpc : v.vpc_id]) == toset(["vpc-0123456789abcdef0", "vpc-0fedcba9876543210"])
    error_message = "Every private_vpc_ids entry must become a vpc block"
  }

  assert {
    condition     = aws_route53_zone.this.comment == "dev private zone"
    error_message = "comment must be passed through"
  }

  assert {
    condition     = aws_route53_zone.this.force_destroy == true
    error_message = "force_destroy must be passed through"
  }

  assert {
    condition     = aws_route53_zone.this.tags["Project"] == "alpha" && aws_route53_zone.this.tags["Name"] == "internal.example.com"
    error_message = "Name must be added to the given tags"
  }

  assert {
    condition     = length(output.name_servers) == 0
    error_message = "name_servers must be empty for a private zone"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "trailing_dot_rejected" {
  command = plan

  variables {
    name = "dev.example.com."
  }

  expect_failures = [var.name]
}

run "invalid_name_rejected" {
  command = plan

  variables {
    name = "dev_example!.com"
  }

  expect_failures = [var.name]
}

run "single_label_name_rejected" {
  command = plan

  variables {
    name = "localhost"
  }

  expect_failures = [var.name]
}

run "invalid_vpc_id_rejected" {
  command = plan

  variables {
    private_vpc_ids = ["subnet-0123456789abcdef0"]
  }

  expect_failures = [var.private_vpc_ids]
}
