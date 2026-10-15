mock_provider "aws" {}

override_resource {
  target          = aws_security_group.this["alb"]
  override_during = plan
  values = {
    id  = "sg-0000000000000alb1"
    arn = "arn:aws:ec2:ap-northeast-1:111111111111:security-group/sg-0000000000000alb1"
  }
}

override_resource {
  target          = aws_security_group.this["api"]
  override_during = plan
  values = {
    id  = "sg-0000000000000api1"
    arn = "arn:aws:ec2:ap-northeast-1:111111111111:security-group/sg-0000000000000api1"
  }
}

override_resource {
  target          = aws_security_group.this["db"]
  override_during = plan
  values = {
    id  = "sg-00000000000000db1"
    arn = "arn:aws:ec2:ap-northeast-1:111111111111:security-group/sg-00000000000000db1"
  }
}

variables {
  vpc_id = "vpc-0123456789abcdef0"

  security_groups = {
    alb = { name = "alpha-dev-alb", description = "ALB" }
    api = { name = "alpha-dev-api", description = "api service" }
    db  = { name = "alpha-dev-db", description = "database" }
  }

  rules = {
    alb_in_https = { security_group = "alb", type = "ingress", description = "clients", from_port = 443, cidr_ipv4 = "0.0.0.0/0", allow_internet = true }
    alb_out_api  = { security_group = "alb", type = "egress", description = "to api", from_port = 8080, to_port = 8081, peer_group = "api" }
    api_in_alb   = { security_group = "api", type = "ingress", description = "from alb", from_port = 8080, peer_group = "alb" }
    api_out_db   = { security_group = "api", type = "egress", description = "to db", from_port = 5432, peer_group = "db" }
    db_in_api    = { security_group = "db", type = "ingress", description = "from api", from_port = 5432, peer_group = "api" }
  }
}

run "one_group_per_key" {
  command = plan

  assert {
    condition     = toset(keys(aws_security_group.this)) == toset(["alb", "api", "db"])
    error_message = "One security group per security_groups key"
  }

  assert {
    condition     = aws_security_group.this["api"].name == "alpha-dev-api" && aws_security_group.this["api"].description == "api service" && aws_security_group.this["api"].vpc_id == "vpc-0123456789abcdef0"
    error_message = "name, description and vpc_id must follow the input"
  }

  assert {
    condition     = aws_security_group.this["db"].tags == tomap({ Name = "alpha-dev-db" })
    error_message = "Without tags input the only tag is Name"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_security_group.this["db"].tags == tomap({ Project = "alpha", Name = "alpha-dev-db" })
    error_message = "Group tags must be the input tags plus Name"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["db_in_api"].tags == tomap({ Project = "alpha", Name = "db_in_api" })
    error_message = "Rule tags must be the input tags plus Name set to the rule key"
  }
}

run "rules_split_by_type" {
  command = plan

  assert {
    condition     = toset(keys(aws_vpc_security_group_ingress_rule.this)) == toset(["alb_in_https", "api_in_alb", "db_in_api"])
    error_message = "Ingress rules must be keyed by the rule key and contain only type = ingress"
  }

  assert {
    condition     = toset(keys(aws_vpc_security_group_egress_rule.this)) == toset(["alb_out_api", "api_out_db"])
    error_message = "Egress rules must be keyed by the rule key and contain only type = egress"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["db_in_api"].security_group_id == "sg-00000000000000db1"
    error_message = "A rule must attach to the group named by security_group"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["db_in_api"].description == "from api"
    error_message = "Rule description must follow the input"
  }
}

run "peer_group_resolves_to_id" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["alb_out_api"].referenced_security_group_id == "sg-0000000000000api1"
    error_message = "peer_group api must resolve to the api group id"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["api_in_alb"].referenced_security_group_id == "sg-0000000000000alb1"
    error_message = "peer_group alb must resolve to the alb group id (reverse direction of the same pair)"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["alb_out_api"].cidr_ipv4 == null && aws_vpc_security_group_egress_rule.this["alb_out_api"].prefix_list_id == null
    error_message = "A peer_group rule must not set any other destination"
  }
}

run "external_peer_and_cidr_and_prefix_list" {
  command = plan

  variables {
    rules = {
      ext_group = { security_group = "api", type = "ingress", description = "other stack", from_port = 8080, peer_group_id = "sg-0aaaaaaaaaaaaaaaa" }
      cidr      = { security_group = "api", type = "ingress", description = "office", from_port = 8080, cidr_ipv4 = "10.1.0.0/16" }
      prefix    = { security_group = "api", type = "egress", description = "s3", from_port = 443, prefix_list_id = "pl-0123456789abcdef0" }
    }
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["ext_group"].referenced_security_group_id == "sg-0aaaaaaaaaaaaaaaa" && aws_vpc_security_group_ingress_rule.this["ext_group"].cidr_ipv4 == null
    error_message = "peer_group_id must map to referenced_security_group_id only"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["cidr"].cidr_ipv4 == "10.1.0.0/16" && aws_vpc_security_group_ingress_rule.this["cidr"].referenced_security_group_id == null
    error_message = "cidr_ipv4 must map to cidr_ipv4 only"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["prefix"].prefix_list_id == "pl-0123456789abcdef0" && aws_vpc_security_group_egress_rule.this["prefix"].cidr_ipv4 == null
    error_message = "prefix_list_id must map to prefix_list_id only"
  }
}

run "to_port_defaults_to_from_port" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["alb_in_https"].from_port == 443 && aws_vpc_security_group_ingress_rule.this["alb_in_https"].to_port == 443
    error_message = "to_port must default to from_port"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["alb_out_api"].from_port == 8080 && aws_vpc_security_group_egress_rule.this["alb_out_api"].to_port == 8081
    error_message = "An explicit to_port must be kept"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["alb_in_https"].ip_protocol == "tcp"
    error_message = "ip_protocol must default to tcp"
  }
}

run "all_protocol_has_no_port" {
  command = plan

  variables {
    rules = {
      all_out = { security_group = "api", type = "egress", description = "everything", ip_protocol = "-1", cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["all_out"].ip_protocol == "-1"
    error_message = "ip_protocol -1 must be passed through"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["all_out"].from_port == null && aws_vpc_security_group_egress_rule.this["all_out"].to_port == null
    error_message = "ip_protocol -1 must have null from_port and to_port"
  }
}

run "udp_and_port_boundaries_pass" {
  command = plan

  variables {
    rules = {
      dns      = { security_group = "api", type = "egress", description = "dns", ip_protocol = "udp", from_port = 0, to_port = 65535, cidr_ipv4 = "10.0.0.0/8" }
      one_port = { security_group = "api", type = "egress", description = "same", from_port = 80, to_port = 80, cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["dns"].to_port == 65535 && aws_vpc_security_group_egress_rule.this["dns"].from_port == 0
    error_message = "Ports 0 and 65535 are valid boundaries"
  }
}

run "ingress_internet_with_flag" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["alb_in_https"].cidr_ipv4 == "0.0.0.0/0"
    error_message = "Ingress to 0.0.0.0/0 with allow_internet = true must pass"
  }
}

run "egress_internet_without_flag" {
  command = plan

  variables {
    rules = {
      api_out_https = { security_group = "api", type = "egress", description = "AWS APIs", from_port = 443, cidr_ipv4 = "0.0.0.0/0" }
    }
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["api_out_https"].cidr_ipv4 == "0.0.0.0/0"
    error_message = "Egress to 0.0.0.0/0 must not need allow_internet"
  }
}

run "ingress_non_default_cidr_without_flag" {
  command = plan

  variables {
    rules = {
      office = { security_group = "api", type = "ingress", description = "office", from_port = 443, cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["office"].cidr_ipv4 == "10.0.0.0/8"
    error_message = "Ingress from a private CIDR needs no allow_internet"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.security_group_ids == tomap({ alb = "sg-0000000000000alb1", api = "sg-0000000000000api1", db = "sg-00000000000000db1" })
    error_message = "security_group_ids must be keyed like security_groups"
  }

  assert {
    condition     = toset(keys(output.security_group_arns)) == toset(["alb", "api", "db"]) && output.security_group_arns["api"] == "arn:aws:ec2:ap-northeast-1:111111111111:security-group/sg-0000000000000api1"
    error_message = "security_group_arns must be keyed like security_groups and carry the group ARN"
  }
}

run "no_rules_creates_groups_only" {
  command = plan

  variables {
    rules = {}
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 0 && length(aws_vpc_security_group_egress_rule.this) == 0 && length(aws_security_group.this) == 3
    error_message = "Empty rules must create groups and no rules"
  }
}
