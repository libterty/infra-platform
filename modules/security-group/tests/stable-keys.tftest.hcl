mock_provider "aws" {}

# Rules are addressed by their map key, never by position, so adding or removing one rule
# must leave every other rule address and attribute untouched.

variables {
  vpc_id = "vpc-0123456789abcdef0"

  security_groups = {
    alb = { name = "alpha-dev-alb", description = "ALB" }
    api = { name = "alpha-dev-api", description = "api service" }
  }

  rules = {
    a_first  = { security_group = "alb", type = "ingress", description = "first", from_port = 443, cidr_ipv4 = "10.0.0.0/8" }
    c_last   = { security_group = "api", type = "ingress", description = "last", from_port = 8080, cidr_ipv4 = "10.1.0.0/16" }
    b_middle = { security_group = "api", type = "egress", description = "middle", from_port = 443, cidr_ipv4 = "10.2.0.0/16" }
  }
}

run "baseline_keys" {
  command = plan

  assert {
    condition     = toset(keys(aws_vpc_security_group_ingress_rule.this)) == toset(["a_first", "c_last"]) && toset(keys(aws_vpc_security_group_egress_rule.this)) == toset(["b_middle"])
    error_message = "Baseline keys must equal the rule keys"
  }
}

run "adding_a_rule_in_the_middle_keeps_other_addresses" {
  command = plan

  variables {
    rules = {
      a_first  = { security_group = "alb", type = "ingress", description = "first", from_port = 443, cidr_ipv4 = "10.0.0.0/8" }
      b_added  = { security_group = "alb", type = "ingress", description = "added in the middle", from_port = 80, cidr_ipv4 = "10.9.0.0/16" }
      c_last   = { security_group = "api", type = "ingress", description = "last", from_port = 8080, cidr_ipv4 = "10.1.0.0/16" }
      b_middle = { security_group = "api", type = "egress", description = "middle", from_port = 443, cidr_ipv4 = "10.2.0.0/16" }
    }
  }

  assert {
    condition     = toset(keys(aws_vpc_security_group_ingress_rule.this)) == toset(["a_first", "b_added", "c_last"])
    error_message = "Only the added key may appear in the ingress set"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["a_first"].cidr_ipv4 == "10.0.0.0/8" && aws_vpc_security_group_ingress_rule.this["c_last"].cidr_ipv4 == "10.1.0.0/16" && aws_vpc_security_group_egress_rule.this["b_middle"].cidr_ipv4 == "10.2.0.0/16"
    error_message = "Existing rules must keep their address and attributes when a rule is added"
  }
}

run "removing_a_rule_keeps_other_addresses" {
  command = plan

  variables {
    rules = {
      a_first = { security_group = "alb", type = "ingress", description = "first", from_port = 443, cidr_ipv4 = "10.0.0.0/8" }
      c_last  = { security_group = "api", type = "ingress", description = "last", from_port = 8080, cidr_ipv4 = "10.1.0.0/16" }
    }
  }

  assert {
    condition     = toset(keys(aws_vpc_security_group_ingress_rule.this)) == toset(["a_first", "c_last"]) && length(aws_vpc_security_group_egress_rule.this) == 0
    error_message = "Removing b_middle must not rename or drop any other rule"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["c_last"].from_port == 8080
    error_message = "A rule after the removed one must keep its attributes"
  }
}

run "changing_a_rule_type_moves_it_between_resources" {
  command = plan

  variables {
    rules = {
      a_first  = { security_group = "alb", type = "ingress", description = "first", from_port = 443, cidr_ipv4 = "10.0.0.0/8" }
      c_last   = { security_group = "api", type = "ingress", description = "last", from_port = 8080, cidr_ipv4 = "10.1.0.0/16" }
      b_middle = { security_group = "api", type = "ingress", description = "middle", from_port = 443, cidr_ipv4 = "10.2.0.0/16" }
    }
  }

  assert {
    condition     = toset(keys(aws_vpc_security_group_ingress_rule.this)) == toset(["a_first", "b_middle", "c_last"]) && length(aws_vpc_security_group_egress_rule.this) == 0
    error_message = "A rule that changes type must leave the other rules where they are"
  }
}
