mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  vpc_cidr            = "10.10.0.0/16"
  azs                 = ["ap-northeast-1a", "ap-northeast-1c"]
  alb_ingress         = { cidrs = ["203.0.113.0/24"] }
}

override_module {
  target = module.in
  outputs = {
    strings = { alarm_topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms" }
    lists   = {}
  }
}

# Computed IDs are unknown at plan time, so the VPC module gets fixed outputs.
override_module {
  target = module.vpc
  outputs = {
    vpc_id   = "vpc-0123456789abcdef0"
    vpc_cidr = "10.10.0.0/16"
    subnet_ids = {
      public = ["subnet-0aaaaaaa00000001", "subnet-0aaaaaaa00000002"]
      app    = ["subnet-0bbbbbbb00000001", "subnet-0bbbbbbb00000002"]
      agent  = ["subnet-0ccccccc00000001", "subnet-0ccccccc00000002"]
      db     = ["subnet-0ddddddd00000001", "subnet-0ddddddd00000002"]
    }
    route_table_ids = {
      public = ["rtb-0aaaaaaa00000001", "rtb-0aaaaaaa00000002"]
      app    = ["rtb-0bbbbbbb00000001", "rtb-0bbbbbbb00000002"]
      agent  = ["rtb-0ccccccc00000001", "rtb-0ccccccc00000002"]
      db     = ["rtb-0ddddddd00000001", "rtb-0ddddddd00000002"]
    }
    nat_gateway_ids = ["nat-0123456789abcdef0", "nat-0123456789abcdef1"]
  }
}

override_data {
  target = data.aws_prefix_list.s3
  values = { id = "pl-0123456789abcdef0" }
}

# ---- reads ----

run "reads_only_the_alarm_topic" {
  command = plan

  assert {
    condition     = local.ssm_input_strings == { alarm_topic_arn = "foundation/alarm_topic_arn" }
    error_message = "network must read foundation/alarm_topic_arn and nothing else"
  }
}

# ---- VPC ----

run "four_tiers_with_the_expected_types" {
  command = plan

  assert {
    condition     = { for t, s in local.vpc_subnets : t => s.type } == { public = "public", app = "private", agent = "private", db = "isolated" }
    error_message = "public is public, app and agent are private (NAT egress), db is isolated"
  }

  assert {
    condition     = local.vpc.nat_mode == "per_az" && local.vpc.cidr == "10.10.0.0/16" && local.vpc.gateway_endpoints == toset(["s3"])
    error_message = "The VPC must default to a NAT per AZ and carry the S3 gateway endpoint"
  }
}

run "nat_can_be_turned_off" {
  command = plan

  variables {
    nat_mode = "none"
  }

  assert {
    condition     = local.vpc.nat_mode == "none"
    error_message = "nat_mode must reach the vpc module"
  }
}

run "nat_mode_single_is_rejected" {
  command = plan

  variables {
    nat_mode = "single"
  }

  expect_failures = [var.nat_mode]
}

run "one_az_is_rejected" {
  command = plan

  variables {
    azs = ["ap-northeast-1a"]
  }

  expect_failures = [var.azs]
}

run "four_azs_are_rejected_because_the_layout_has_three_slots_per_tier" {
  command = plan

  variables {
    azs = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d", "ap-northeast-1e"]
  }

  expect_failures = [var.azs]
}

run "vpc_cidr_must_be_a_slash_16" {
  command = plan

  variables {
    vpc_cidr = "10.10.0.0/20"
  }

  expect_failures = [var.vpc_cidr]
}

# ---- Bedrock interface endpoints ----

run "bedrock_endpoints_use_the_vpc_cidr_and_the_app_subnets" {
  command = plan

  assert {
    condition     = local.interface_endpoints.services == toset(["bedrock", "bedrock-agentcore", "bedrock-runtime"])
    error_message = "The three Bedrock endpoints are created by default"
  }

  assert {
    condition     = local.interface_endpoints.allowed_cidrs == ["10.10.0.0/16"]
    error_message = "Only the VPC itself may reach the endpoints"
  }

  assert {
    condition     = local.interface_endpoints.subnet_ids == ["subnet-0bbbbbbb00000001", "subnet-0bbbbbbb00000002"]
    error_message = "Endpoint interfaces belong in the app subnets"
  }
}

run "bedrock_endpoints_can_be_turned_off" {
  command = plan

  variables {
    bedrock_endpoints_enabled = false
  }

  assert {
    condition     = length(local.interface_endpoints.services) == 0
    error_message = "Without the switch no endpoint service is requested"
  }
}

# ---- security groups ----

run "seven_security_groups" {
  command = plan

  assert {
    condition     = toset(keys(local.security_groups)) == toset(["alb", "app", "agent", "db", "db_proxy", "cache", "bastion"])
    error_message = "One group per tier, plus a separate group for the RDS Proxy"
  }
}

run "data_stores_and_the_alb_have_no_open_egress" {
  command = plan

  variables {
    bastion_enabled = true
  }

  assert {
    condition = length([
      for r in values(local.sg_rules) : r
      if r.type == "egress" && contains(["alb", "db", "db_proxy", "cache"], r.security_group) && (r.cidr_ipv4 == "0.0.0.0/0" || r.ip_protocol == "-1")
    ]) == 0
    error_message = "ALB and data store groups must not have egress to 0.0.0.0/0 or on all protocols (J6)"
  }

  assert {
    condition     = length([for r in values(local.sg_rules) : r if r.ip_protocol == "-1"]) == 0
    error_message = "No rule may allow all protocols"
  }

  assert {
    condition     = length([for r in values(local.sg_rules) : r if r.type == "egress" && contains(["db", "cache"], r.security_group)]) == 0
    error_message = "The database and the caches never open connections, so they need no egress rule at all"
  }
}

run "alb_egress_goes_only_to_the_app_group_on_the_app_port" {
  command = plan

  assert {
    condition = [
      for r in values(local.sg_rules) : "${r.peer_group}:${r.from_port}" if r.type == "egress" && r.security_group == "alb"
    ] == ["app:8080"]
    error_message = "The ALB may only reach the app group on app_port"
  }
}

run "database_is_reachable_only_from_the_proxy" {
  command = plan

  variables {
    bastion_enabled = true
  }

  assert {
    condition = [
      for r in values(local.sg_rules) : r.peer_group if r.type == "ingress" && r.security_group == "db"
    ] == ["db_proxy"]
    error_message = "The Aurora cluster must only accept connections from the RDS Proxy group"
  }

  assert {
    condition = toset([
      for r in values(local.sg_rules) : r.peer_group if r.type == "ingress" && r.security_group == "db_proxy"
    ]) == toset(["app", "agent", "bastion"])
    error_message = "The Proxy accepts app, agent and bastion, nothing else"
  }

  assert {
    condition = toset([
      for r in values(local.sg_rules) : r.peer_group if r.type == "ingress" && r.security_group == "cache"
    ]) == toset(["app", "bastion"])
    error_message = "The caches accept app and bastion, nothing else"
  }
}

run "bastion_has_no_rules_when_disabled" {
  command = plan

  assert {
    condition     = length([for r in values(local.sg_rules) : r if r.security_group == "bastion" || r.peer_group == "bastion"]) == 0
    error_message = "A disabled bastion must not open any path"
  }
}

run "bastion_reaches_the_proxy_and_the_cache_when_enabled" {
  command = plan

  variables {
    bastion_enabled = true
  }

  assert {
    condition = toset([
      for r in values(local.sg_rules) : "${r.peer_group}:${r.from_port}" if r.type == "egress" && r.security_group == "bastion" && r.peer_group != null
    ]) == toset(["db_proxy:5432", "cache:6379"])
    error_message = "The bastion forwards to the Proxy and clears the cache, on those ports only"
  }
}

run "only_the_alb_accepts_the_outside_and_only_from_the_given_sources" {
  command = plan

  assert {
    condition     = toset([for r in values(local.sg_rules) : r.security_group if r.type == "ingress" && r.cidr_ipv4 != null]) == toset(["alb"])
    error_message = "Ingress from a CIDR is for the ALB only"
  }

  assert {
    condition     = toset([for r in values(local.sg_rules) : r.cidr_ipv4 if r.type == "ingress" && r.security_group == "alb"]) == toset(["203.0.113.0/24"])
    error_message = "The ALB accepts the configured CIDR only"
  }

  assert {
    condition     = toset([for r in values(local.sg_rules) : r.from_port if r.type == "ingress" && r.security_group == "alb"]) == toset([80, 443])
    error_message = "The ALB listens on 443 and 80"
  }

  assert {
    condition     = alltrue([for r in values(local.sg_rules) : !r.allow_internet])
    error_message = "A specific CIDR must not be marked as open to the internet"
  }
}

run "an_open_alb_is_explicit" {
  command = plan

  variables {
    alb_ingress = { cidrs = ["0.0.0.0/0"] }
  }

  assert {
    condition     = alltrue([for r in values(local.sg_rules) : r.allow_internet if r.type == "ingress" && r.cidr_ipv4 == "0.0.0.0/0"])
    error_message = "0.0.0.0/0 on the ALB must set allow_internet so the module accepts it knowingly"
  }
}

run "alb_accepts_prefix_lists" {
  command = plan

  variables {
    alb_ingress = { prefix_list_ids = ["pl-0aaaaaaa00000001"] }
  }

  assert {
    condition     = toset([for r in values(local.sg_rules) : r.prefix_list_id if r.type == "ingress" && r.security_group == "alb"]) == toset(["pl-0aaaaaaa00000001"])
    error_message = "A prefix list must be usable as the ALB source"
  }
}

run "alb_ingress_needs_a_source" {
  command = plan

  variables {
    alb_ingress = {}
  }

  expect_failures = [var.alb_ingress]
}

run "app_and_agent_reach_aws_apis_through_the_nat" {
  command = plan

  assert {
    condition = alltrue([
      for k in ["app", "agent"] : length([
        for r in values(local.sg_rules) : r
        if r.type == "egress" && r.security_group == k && r.cidr_ipv4 == "0.0.0.0/0" && r.from_port == 443
      ]) == 1
    ])
    error_message = "With a NAT, app and agent get one 443 egress rule to the internet"
  }
}

run "without_a_nat_egress_stays_inside_the_vpc_and_the_s3_prefix_list" {
  command = plan

  variables {
    nat_mode        = "none"
    bastion_enabled = true
  }

  assert {
    condition     = length([for r in values(local.sg_rules) : r if r.type == "egress" && r.cidr_ipv4 == "0.0.0.0/0"]) == 0
    error_message = "Without a NAT nothing may keep an egress rule to 0.0.0.0/0"
  }

  assert {
    condition = alltrue([
      for k in ["app", "agent", "bastion"] : length([
        for r in values(local.sg_rules) : r
        if r.type == "egress" && r.security_group == k && r.from_port == 443 && (r.cidr_ipv4 == "10.10.0.0/16" || r.prefix_list_id == "pl-0123456789abcdef0")
      ]) == 2
    ])
    error_message = "Without a NAT, 443 reaches the interface endpoints (VPC CIDR) and S3 (gateway endpoint prefix list), image layers come from S3"
  }
}

# ---- peering ----

run "no_peering_creates_nothing_and_publishes_an_empty_map" {
  command = plan

  assert {
    condition     = length(module.peering) == 0
    error_message = "peering = null must not create a peering connection"
  }

  assert {
    condition     = local.published_strings.peering_connections == "{}"
    error_message = "Without a peering the published value is an empty JSON object"
  }

  assert {
    condition     = length([for r in values(local.sg_rules) : r if startswith(r.description, "peer")]) == 0
    error_message = "Without a peering no rule may point at the peer network"
  }
}

run "peering_routes_the_app_and_agent_tiers" {
  command = plan

  variables {
    peering = {
      peer_vpc_id   = "vpc-0fedcba9876543210"
      peer_owner_id = "444444444444"
      peer_cidrs    = ["10.250.0.0/16"]
    }
  }

  assert {
    condition     = length(module.peering) == 1
    error_message = "A peering object must create one connection"
  }

  assert {
    condition     = local.peering_route_table_ids == ["rtb-0bbbbbbb00000001", "rtb-0bbbbbbb00000002", "rtb-0ccccccc00000001", "rtb-0ccccccc00000002"]
    error_message = "Routes to the peer network go on the app and agent route tables, not on public or db"
  }

  assert {
    condition = [
      for r in values(local.sg_rules) : r.cidr_ipv4 if r.type == "egress" && r.security_group == "app" && r.description == "peer network over the peering connection"
    ] == ["10.250.0.0/16"]
    error_message = "The app group (ECS tasks and Lambda) may reach the peer CIDR on 443"
  }
}

run "peering_owner_must_be_an_account_id" {
  command = plan

  variables {
    peering = {
      peer_vpc_id   = "vpc-0fedcba9876543210"
      peer_owner_id = "not-an-account"
      peer_cidrs    = ["10.250.0.0/16"]
    }
  }

  expect_failures = [var.peering]
}

# ---- NAT alarms ----

run "one_nat_alarm_per_nat_gateway" {
  command = plan

  assert {
    condition     = toset(keys(local.nat_alarms)) == toset(["nat_1_port_allocation_errors", "nat_2_port_allocation_errors"])
    error_message = "A NAT per AZ means one port-allocation alarm per NAT"
  }

  assert {
    condition     = alltrue([for a in values(local.nat_alarms) : a.metric.namespace == "AWS/NATGateway" && a.metric.metric_name == "ErrorPortAllocation"])
    error_message = "The alarms watch ErrorPortAllocation of the NAT gateway"
  }

  assert {
    condition     = local.nat_alarms["nat_2_port_allocation_errors"].metric.dimensions == { NatGatewayId = "nat-0123456789abcdef1" }
    error_message = "Each alarm must be bound to its own NAT gateway"
  }
}

run "no_nat_no_nat_alarm" {
  command = plan

  variables {
    nat_mode = "none"
  }

  override_module {
    target = module.vpc
    outputs = {
      vpc_id   = "vpc-0123456789abcdef0"
      vpc_cidr = "10.10.0.0/16"
      subnet_ids = {
        public = ["subnet-0aaaaaaa00000001", "subnet-0aaaaaaa00000002"]
        app    = ["subnet-0bbbbbbb00000001", "subnet-0bbbbbbb00000002"]
        agent  = ["subnet-0ccccccc00000001", "subnet-0ccccccc00000002"]
        db     = ["subnet-0ddddddd00000001", "subnet-0ddddddd00000002"]
      }
      route_table_ids = {
        public = ["rtb-0aaaaaaa00000001", "rtb-0aaaaaaa00000002"]
        app    = ["rtb-0bbbbbbb00000001", "rtb-0bbbbbbb00000002"]
        agent  = ["rtb-0ccccccc00000001", "rtb-0ccccccc00000002"]
        db     = ["rtb-0ddddddd00000001", "rtb-0ddddddd00000002"]
      }
      nat_gateway_ids = []
    }
  }

  assert {
    condition     = length(local.nat_alarms) == 0
    error_message = "Without a NAT there is no alarm to create"
  }

  assert {
    condition     = length(module.nat_alarms.alarm_names) == 0
    error_message = "The alarm module must create nothing when nat_mode is none"
  }
}

# ---- publishing ----

run "publishes_every_vpc_subnet_and_group_key" {
  command = plan

  override_module {
    target = module.sg
    outputs = {
      security_group_ids = {
        alb      = "sg-0aaaaaaa00000001"
        app      = "sg-0aaaaaaa00000002"
        agent    = "sg-0aaaaaaa00000003"
        db       = "sg-0aaaaaaa00000004"
        db_proxy = "sg-0aaaaaaa00000005"
        cache    = "sg-0aaaaaaa00000006"
        bastion  = "sg-0aaaaaaa00000007"
      }
    }
  }

  assert {
    condition = local.published_strings == {
      vpc_id              = "vpc-0123456789abcdef0"
      vpc_cidr            = "10.10.0.0/16"
      alb_sg_id           = "sg-0aaaaaaa00000001"
      app_sg_id           = "sg-0aaaaaaa00000002"
      agent_sg_id         = "sg-0aaaaaaa00000003"
      db_sg_id            = "sg-0aaaaaaa00000004"
      db_proxy_sg_id      = "sg-0aaaaaaa00000005"
      cache_sg_id         = "sg-0aaaaaaa00000006"
      bastion_sg_id       = "sg-0aaaaaaa00000007"
      peering_connections = "{}"
    }
    error_message = "Each published string must come from the matching module output"
  }

  assert {
    condition = local.published_lists == {
      public_subnet_ids = ["subnet-0aaaaaaa00000001", "subnet-0aaaaaaa00000002"]
      app_subnet_ids    = ["subnet-0bbbbbbb00000001", "subnet-0bbbbbbb00000002"]
      agent_subnet_ids  = ["subnet-0ccccccc00000001", "subnet-0ccccccc00000002"]
      db_subnet_ids     = ["subnet-0ddddddd00000001", "subnet-0ddddddd00000002"]
    }
    error_message = "Each subnet list must come from the matching tier, in AZ order"
  }

  assert {
    condition = module.ssm_publish.names == {
      vpc_id              = "/example/dev/network/vpc_id"
      vpc_cidr            = "/example/dev/network/vpc_cidr"
      alb_sg_id           = "/example/dev/network/alb_sg_id"
      app_sg_id           = "/example/dev/network/app_sg_id"
      agent_sg_id         = "/example/dev/network/agent_sg_id"
      db_sg_id            = "/example/dev/network/db_sg_id"
      db_proxy_sg_id      = "/example/dev/network/db_proxy_sg_id"
      cache_sg_id         = "/example/dev/network/cache_sg_id"
      bastion_sg_id       = "/example/dev/network/bastion_sg_id"
      peering_connections = "/example/dev/network/peering_connections"
      public_subnet_ids   = "/example/dev/network/public_subnet_ids"
      app_subnet_ids      = "/example/dev/network/app_subnet_ids"
      agent_subnet_ids    = "/example/dev/network/agent_subnet_ids"
      db_subnet_ids       = "/example/dev/network/db_subnet_ids"
    }
    error_message = "ssm-publish must write the fourteen network keys under the network path"
  }
}
