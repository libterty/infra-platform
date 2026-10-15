mock_provider "aws" {}

variables {
  vpc_id = "vpc-0123456789abcdef0"

  security_groups = {
    alb = { name = "alpha-dev-alb", description = "ALB" }
    api = { name = "alpha-dev-api", description = "api service" }
  }

  rules = {}
}

run "vpc_id_format" {
  command = plan

  variables {
    vpc_id = "not-a-vpc"
  }

  expect_failures = [var.vpc_id]
}

run "groups_required_empty" {
  command = plan

  variables {
    security_groups = {}
  }

  expect_failures = [var.security_groups]
}

run "group_key_must_be_snake_case" {
  command = plan

  variables {
    security_groups = {
      Alb = { name = "alpha-dev-alb", description = "ALB" }
    }
  }

  expect_failures = [var.security_groups]
}

run "group_key_snake_case_passes" {
  command = plan

  variables {
    security_groups = {
      db_proxy_2 = { name = "alpha-dev-db-proxy", description = "proxy" }
    }
  }

  assert {
    condition     = contains(keys(aws_security_group.this), "db_proxy_2")
    error_message = "snake_case keys with digits and underscores must pass"
  }
}

run "rule_group_must_exist" {
  command = plan

  variables {
    rules = {
      r = { security_group = "nope", type = "ingress", description = "x", from_port = 80, cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  expect_failures = [var.rules]
}

run "rule_peer_group_must_exist" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "ingress", description = "x", from_port = 80, peer_group = "nope" }
    }
  }

  expect_failures = [var.rules]
}

run "rule_peer_group_existing_passes" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "ingress", description = "x", from_port = 80, peer_group = "alb" }
    }
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 1
    error_message = "A rule between two existing groups must pass"
  }
}

run "exactly_one_peer_none" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "ingress", description = "x", from_port = 80 }
    }
  }

  expect_failures = [var.rules]
}

run "exactly_one_peer_two_given" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "ingress", description = "x", from_port = 80, peer_group = "alb", cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  expect_failures = [var.rules]
}

run "exactly_one_peer_each_kind_passes" {
  command = plan

  variables {
    rules = {
      a = { security_group = "api", type = "egress", description = "x", from_port = 80, peer_group = "alb" }
      b = { security_group = "api", type = "egress", description = "x", from_port = 80, peer_group_id = "sg-0aaaaaaaaaaaaaaaa" }
      c = { security_group = "api", type = "egress", description = "x", from_port = 80, cidr_ipv4 = "10.0.0.0/8" }
      d = { security_group = "api", type = "egress", description = "x", from_port = 80, prefix_list_id = "pl-0123456789abcdef0" }
    }
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.this) == 4
    error_message = "Each of the four peer kinds must pass on its own"
  }
}

run "type_values_both_rejected" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "both", description = "x", from_port = 80, cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  expect_failures = [var.rules]
}

run "protocol_values_icmp_rejected" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "ingress", description = "x", ip_protocol = "icmp", from_port = 8, cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  expect_failures = [var.rules]
}

run "tcp_needs_from_port" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "ingress", description = "x", cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  expect_failures = [var.rules]
}

run "to_port_below_from_port" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "ingress", description = "x", from_port = 8080, to_port = 8079, cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  expect_failures = [var.rules]
}

run "from_port_out_of_range" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "ingress", description = "x", from_port = 70000, cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  expect_failures = [var.rules]
}

run "negative_from_port_rejected" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "ingress", description = "x", from_port = -1, cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  expect_failures = [var.rules]
}

run "to_port_out_of_range" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "ingress", description = "x", from_port = 80, to_port = 65536, cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  expect_failures = [var.rules]
}

run "all_protocol_with_port_rejected" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "egress", description = "x", ip_protocol = "-1", from_port = 443, cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  expect_failures = [var.rules]
}

run "all_protocol_with_to_port_only_rejected" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "egress", description = "x", ip_protocol = "-1", to_port = 443, cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  expect_failures = [var.rules]
}

run "ingress_internet_needs_flag" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "ingress", description = "x", from_port = 443, cidr_ipv4 = "0.0.0.0/0" }
    }
  }

  expect_failures = [var.rules]
}

run "ingress_internet_flag_false_rejected" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "ingress", description = "x", from_port = 443, cidr_ipv4 = "0.0.0.0/0", allow_internet = false }
    }
  }

  expect_failures = [var.rules]
}

run "ingress_internet_all_protocol_needs_flag" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "ingress", description = "x", ip_protocol = "-1", cidr_ipv4 = "0.0.0.0/0" }
    }
  }

  expect_failures = [var.rules]
}

run "cidr_prefix_too_long" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "ingress", description = "x", from_port = 80, cidr_ipv4 = "10.0.0.0/33" }
    }
  }

  expect_failures = [var.rules]
}

run "cidr_not_a_cidr" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "ingress", description = "x", from_port = 80, cidr_ipv4 = "not-a-cidr" }
    }
  }

  expect_failures = [var.rules]
}

run "cidr_ipv6_rejected" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "ingress", description = "x", from_port = 80, cidr_ipv4 = "2001:db8::/32" }
    }
  }

  expect_failures = [var.rules]
}

run "cidr_bad_octet_rejected" {
  command = plan

  variables {
    rules = {
      r = { security_group = "api", type = "ingress", description = "x", from_port = 80, cidr_ipv4 = "10.0.0.300/24" }
    }
  }

  expect_failures = [var.rules]
}

run "cidr_boundaries_pass" {
  command = plan

  variables {
    rules = {
      a = { security_group = "api", type = "ingress", description = "x", from_port = 80, cidr_ipv4 = "10.0.0.1/32" }
      b = { security_group = "api", type = "egress", description = "x", from_port = 80, cidr_ipv4 = "0.0.0.0/0" }
    }
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 1 && length(aws_vpc_security_group_egress_rule.this) == 1
    error_message = "/32 and 0.0.0.0/0 are valid CIDRs"
  }
}
