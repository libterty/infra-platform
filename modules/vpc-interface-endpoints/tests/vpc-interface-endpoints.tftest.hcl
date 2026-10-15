mock_provider "aws" {}

variables {
  name          = "alpha-dev"
  vpc_id        = "vpc-0123456789abcdef0"
  allowed_cidrs = ["10.0.0.0/20"]
  subnet_ids    = ["subnet-0aaa1111", "subnet-0bbb2222"]
  services      = ["ecr.api", "logs"]
}

run "one_interface_endpoint_per_service" {
  command = apply

  assert {
    condition     = toset(keys(aws_vpc_endpoint.this)) == toset(["ecr.api", "logs"])
    error_message = "One endpoint per service"
  }

  assert {
    condition = alltrue([
      for e in values(aws_vpc_endpoint.this) :
      e.vpc_endpoint_type == "Interface" && e.private_dns_enabled == true && e.vpc_id == "vpc-0123456789abcdef0" &&
      toset(e.subnet_ids) == toset(["subnet-0aaa1111", "subnet-0bbb2222"]) &&
      toset(e.security_group_ids) == toset([aws_security_group.this[0].id])
    ])
    error_message = "Endpoints must be Interface type with private DNS, the given subnets and the module SG"
  }

  assert {
    condition     = aws_vpc_endpoint.this["logs"].service_name == "com.amazonaws.${data.aws_region.current.region}.logs"
    error_message = "service_name must be com.amazonaws.<region>.<service>"
  }

  assert {
    condition     = aws_vpc_endpoint.this["logs"].tags["Name"] == "alpha-dev-logs"
    error_message = "Endpoint Name tag is <name>-<service>"
  }
}

run "sg_has_only_https_ingress_from_allowed_cidrs" {
  command = apply

  variables {
    allowed_cidrs = ["10.0.0.0/20", "172.16.0.0/16"]
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.https) == 2 && toset(keys(aws_vpc_security_group_ingress_rule.https)) == toset(["10.0.0.0/20", "172.16.0.0/16"])
    error_message = "One ingress rule per allowed CIDR"
  }

  assert {
    condition = alltrue([
      for r in values(aws_vpc_security_group_ingress_rule.https) :
      r.from_port == 443 && r.to_port == 443 && r.ip_protocol == "tcp" && r.security_group_id == aws_security_group.this[0].id
    ])
    error_message = "Every rule is 443/tcp on the module SG"
  }

  assert {
    condition     = aws_security_group.this[0].vpc_id == "vpc-0123456789abcdef0" && output.security_group_id == aws_security_group.this[0].id
    error_message = "SG lives in vpc_id and is exposed as an output"
  }

  assert {
    condition     = length(aws_security_group.this[0].egress) == 0 && length(aws_security_group.this[0].ingress) == 0
    error_message = "SG must have no inline rules"
  }
}

run "no_egress_rule_resource" {
  command = plan

  assert {
    condition     = length(aws_security_group.this) == 1 && length(aws_vpc_security_group_ingress_rule.https) == 1
    error_message = "Only an SG and ingress rules are created; egress is not managed"
  }
}

run "empty_services_creates_nothing" {
  command = apply

  variables {
    services = []
  }

  assert {
    condition     = length(aws_vpc_endpoint.this) == 0 && length(aws_security_group.this) == 0 && length(aws_vpc_security_group_ingress_rule.https) == 0
    error_message = "services = [] must create no endpoint, SG or rule"
  }

  assert {
    condition     = output.security_group_id == null && length(output.endpoint_ids) == 0
    error_message = "security_group_id must be null and endpoint_ids empty"
  }
}

run "endpoint_ids_keyed_by_service" {
  command = apply

  assert {
    condition     = toset(keys(output.endpoint_ids)) == toset(["ecr.api", "logs"]) && output.endpoint_ids["logs"] == aws_vpc_endpoint.this["logs"].id
    error_message = "endpoint_ids must be keyed by service name"
  }
}

run "private_dns_false_passes_through" {
  command = plan

  variables {
    private_dns_enabled = false
  }

  assert {
    condition     = alltrue([for e in values(aws_vpc_endpoint.this) : e.private_dns_enabled == false])
    error_message = "private_dns_enabled = false must be passed to every endpoint"
  }
}

run "tags_applied_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_security_group.this[0].tags["Name"] == "alpha-dev-vpce" && aws_security_group.this[0].tags["Project"] == "alpha" && aws_vpc_endpoint.this["logs"].tags["Project"] == "alpha"
    error_message = "Tags are merged with Name on the SG and endpoints"
  }
}

run "service_with_region_prefix_fails" {
  command = plan

  variables {
    services = ["com.amazonaws.ap-northeast-1.logs"]
  }

  expect_failures = [var.services]
}

run "service_short_name_passes" {
  command = plan

  variables {
    services = ["ecr.api"]
  }

  assert {
    condition     = length(aws_vpc_endpoint.this) == 1
    error_message = "ecr.api is a valid service name"
  }
}

run "service_uppercase_fails" {
  command = plan

  variables {
    services = ["Logs"]
  }

  expect_failures = [var.services]
}

run "allowed_cidrs_empty_fails" {
  command = plan

  variables {
    allowed_cidrs = []
  }

  expect_failures = [var.allowed_cidrs]
}

run "allowed_cidrs_open_world_fails" {
  command = plan

  variables {
    allowed_cidrs = ["10.0.0.0/20", "0.0.0.0/0"]
  }

  expect_failures = [var.allowed_cidrs]
}

run "allowed_cidrs_not_cidr_fails" {
  command = plan

  variables {
    allowed_cidrs = ["10.0.0.1"]
  }

  expect_failures = [var.allowed_cidrs]
}

run "allowed_cidrs_bad_octet_fails" {
  command = plan

  variables {
    allowed_cidrs = ["10.0.0.300/24"]
  }

  expect_failures = [var.allowed_cidrs]
}

run "allowed_cidrs_ipv6_fails" {
  command = plan

  variables {
    allowed_cidrs = ["2001:db8::/32"]
  }

  expect_failures = [var.allowed_cidrs]
}

run "allowed_cidrs_single_host_passes" {
  command = plan

  variables {
    allowed_cidrs = ["10.0.0.5/32"]
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.https) == 1
    error_message = "A /32 is a valid allowed CIDR"
  }
}

run "one_subnet_fails" {
  command = plan

  variables {
    subnet_ids = ["subnet-0aaa1111"]
  }

  expect_failures = [var.subnet_ids]
}

run "duplicate_subnets_fail" {
  command = plan

  variables {
    subnet_ids = ["subnet-0aaa1111", "subnet-0aaa1111"]
  }

  expect_failures = [var.subnet_ids]
}

run "three_subnets_pass" {
  command = plan

  variables {
    subnet_ids = ["subnet-0aaa1111", "subnet-0bbb2222", "subnet-0ccc3333"]
  }

  assert {
    condition     = alltrue([for e in values(aws_vpc_endpoint.this) : length(e.subnet_ids) == 3])
    error_message = "Three subnets are accepted"
  }
}

run "vpc_id_bad_format_fails" {
  command = plan

  variables {
    vpc_id = "vpc-xyz"
  }

  expect_failures = [var.vpc_id]
}

run "name_uppercase_fails" {
  command = plan

  variables {
    name = "Alpha"
  }

  expect_failures = [var.name]
}

run "name_two_chars_passes" {
  command = plan

  variables {
    name = "ab"
  }

  assert {
    condition     = aws_security_group.this[0].name == "ab-vpce"
    error_message = "A two character name is valid"
  }
}
