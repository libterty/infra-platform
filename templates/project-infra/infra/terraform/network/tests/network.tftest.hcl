mock_provider "aws" {}

variables {
  project             = "alpha"
  env                 = "dev"
  expected_account_id = "111111111111"

  vpc = {
    cidr = "10.20.0.0/20"
    azs  = ["ap-northeast-1a", "ap-northeast-1c"]
    subnets = {
      public = { type = "public", newbits = 6, netnum_base = 0 }
      app    = { type = "private", newbits = 4, netnum_base = 1 }
      data   = { type = "isolated", newbits = 7, netnum_base = 40 }
    }
    nat_mode = "single"
    flow_log = false
  }

  services = {
    api    = { port = 8080, from_alb = true, data_access = ["db"] }
    worker = { port = 9000, callers = ["api"], data_access = ["db"] }
  }

  data_stores = {
    db = { port = 5432, proxy = true }
  }

  alb_ingress = {
    https = true
    cidrs = ["0.0.0.0/0"]
  }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/flow_log_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::alpha-dev-flow-logs-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/services"]
  values = { insecure_value = "api,worker" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
  values = { insecure_value = "[]" }
}

run "reads_only_listed_keys" {
  command = plan

  assert {
    condition = (
      local.ssm_input_strings == { flow_log_bucket_arn = "foundation/flow_log_bucket_arn", agent_runtimes = "containerimage/agent_runtimes" } &&
      local.ssm_input_lists == { services = "containerimage/services" }
    )
    error_message = "network must read the flow log bucket from foundation and the service and Runtime lists from containerimage, nothing else"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      vpc_id              = "/alpha/dev/network/vpc_id"
      vpc_cidr            = "/alpha/dev/network/vpc_cidr"
      nat                 = "/alpha/dev/network/nat"
      interface_endpoints = "/alpha/dev/network/interface_endpoints"
      alb_https           = "/alpha/dev/network/alb_https"
      db_proxy            = "/alpha/dev/network/db_proxy"
      data_access         = "/alpha/dev/network/data_access"
      agent_data_access   = "/alpha/dev/network/agent_data_access"
      sg_alb_id           = "/alpha/dev/network/sg_alb_id"
      sg_api_id           = "/alpha/dev/network/sg_api_id"
      sg_worker_id        = "/alpha/dev/network/sg_worker_id"
      sg_db_id            = "/alpha/dev/network/sg_db_id"
      sg_db_proxy_id      = "/alpha/dev/network/sg_db_proxy_id"
      azs                 = "/alpha/dev/network/azs"
      subnet_ids_public   = "/alpha/dev/network/subnet_ids_public"
      subnet_ids_app      = "/alpha/dev/network/subnet_ids_app"
      subnet_ids_data     = "/alpha/dev/network/subnet_ids_data"
      subnet_cidrs_public = "/alpha/dev/network/subnet_cidrs_public"
      subnet_cidrs_app    = "/alpha/dev/network/subnet_cidrs_app"
      subnet_cidrs_data   = "/alpha/dev/network/subnet_cidrs_data"
    }
    error_message = "ssm-publish must write the contract keys under the network stack path"
  }
}

run "create_mode_publishes_keys" {
  command = plan

  override_module {
    target = module.vpc[0]
    outputs = {
      vpc_id          = "vpc-0123456789abcdef0"
      vpc_cidr        = "10.20.0.0/20"
      azs             = ["ap-northeast-1a", "ap-northeast-1c"]
      subnet_ids      = { public = ["subnet-0pub1", "subnet-0pub2"], app = ["subnet-0app1", "subnet-0app2"], data = ["subnet-0dat1", "subnet-0dat2"] }
      subnet_cidrs    = { public = ["10.20.0.0/26", "10.20.0.64/26"], app = ["10.20.1.0/24", "10.20.2.0/24"], data = ["10.20.5.0/27", "10.20.5.32/27"] }
      nat_gateway_ids = ["nat-0123456789abcdef0"]
    }
  }

  assert {
    condition = toset(keys(local.published_strings)) == toset([
      "vpc_id",
      "vpc_cidr",
      "nat",
      "interface_endpoints",
      "alb_https",
      "db_proxy",
      "data_access",
      "agent_data_access",
      "sg_alb_id",
      "sg_api_id",
      "sg_worker_id",
      "sg_db_id",
      "sg_db_proxy_id",
    ])
    error_message = "Create mode must publish the String keys of the contract"
  }

  assert {
    condition = toset(keys(local.published_lists)) == toset([
      "azs",
      "subnet_ids_public",
      "subnet_ids_app",
      "subnet_ids_data",
      "subnet_cidrs_public",
      "subnet_cidrs_app",
      "subnet_cidrs_data",
    ])
    error_message = "Create mode must publish the StringList keys of the contract"
  }

  assert {
    condition     = tolist(local.published_lists["azs"]) == tolist(["ap-northeast-1a", "ap-northeast-1c"]) && tolist(local.published_lists["subnet_ids_app"]) == tolist(["subnet-0app1", "subnet-0app2"])
    error_message = "Lists must keep the AZ order of the vpc module"
  }

  assert {
    condition     = length(module.vpc) == 1
    error_message = "Create mode must call the vpc module"
  }
}

run "existing_mode_publishes_same_keys" {
  command = plan

  variables {
    vpc = null
    existing = {
      vpc_id = "vpc-0aaaaaaaaaaaaaaaa"
      subnet_ids = {
        public = ["subnet-0pub1", "subnet-0pub2"]
        app    = ["subnet-0app1", "subnet-0app2"]
        data   = ["subnet-0dat1", "subnet-0dat2"]
      }
    }
  }

  override_data {
    target = data.aws_vpc.existing[0]
    values = {
      cidr_block           = "10.50.0.0/16"
      enable_dns_support   = true
      enable_dns_hostnames = true
      cidr_block_associations = [
        {
          association_id = "vpc-cidr-assoc-1"
          cidr_block     = "10.50.0.0/16"
          state          = "associated"
        },
      ]
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.0.0/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.0.64/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.1.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.2.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.5.0/27"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.5.32/27"
    }
  }

  assert {
    condition = toset(keys(local.published_strings)) == toset([
      "vpc_id",
      "vpc_cidr",
      "nat",
      "interface_endpoints",
      "alb_https",
      "db_proxy",
      "data_access",
      "agent_data_access",
      "sg_alb_id",
      "sg_api_id",
      "sg_worker_id",
      "sg_db_id",
      "sg_db_proxy_id",
    ])
    error_message = "Mode A must publish the same String keys as create mode"
  }

  assert {
    condition = toset(keys(local.published_lists)) == toset([
      "azs",
      "subnet_ids_public",
      "subnet_ids_app",
      "subnet_ids_data",
      "subnet_cidrs_public",
      "subnet_cidrs_app",
      "subnet_cidrs_data",
    ])
    error_message = "Mode A must publish the same StringList keys as create mode"
  }

  assert {
    condition     = local.published_strings["vpc_id"] == "vpc-0aaaaaaaaaaaaaaaa" && local.published_strings["vpc_cidr"] == "10.50.0.0/16"
    error_message = "Mode A must publish the registered VPC id and its primary CIDR"
  }

  assert {
    condition     = tolist(local.published_lists["azs"]) == tolist(["ap-northeast-1a", "ap-northeast-1c"])
    error_message = "Mode A must derive the AZ order from the app tier subnets"
  }

  assert {
    condition     = tolist(local.published_lists["subnet_ids_data"]) == tolist(["subnet-0dat1", "subnet-0dat2"]) && tolist(local.published_lists["subnet_cidrs_data"]) == tolist(["10.50.5.0/27", "10.50.5.32/27"])
    error_message = "Mode A must publish the registered subnet IDs and the CIDRs read from the subnets"
  }

  assert {
    condition     = length(module.vpc) == 0
    error_message = "Mode A must not call the vpc module"
  }
}

run "vpc_and_existing_are_exclusive_both_rejected" {
  command = plan

  variables {
    existing = {
      vpc_id = "vpc-0aaaaaaaaaaaaaaaa"
      subnet_ids = {
        public = ["subnet-0pub1", "subnet-0pub2"]
        app    = ["subnet-0app1", "subnet-0app2"]
        data   = ["subnet-0dat1", "subnet-0dat2"]
      }
    }
  }

  expect_failures = [var.existing]
}

run "vpc_and_existing_are_exclusive_none_rejected" {
  command = plan

  variables {
    vpc = null
  }

  expect_failures = [var.existing]
}

run "vpc_only_passes" {
  command = plan

  assert {
    condition     = length(module.vpc) == 1 && length(data.aws_vpc.existing) == 0
    error_message = "Setting only vpc must create the VPC and read nothing"
  }
}

run "contract_tiers_required_create_mode" {
  command = plan

  variables {
    vpc = merge(var.vpc, {
      subnets = {
        public = { type = "public", newbits = 6, netnum_base = 0 }
        app    = { type = "private", newbits = 4, netnum_base = 1 }
      }
    })
  }

  expect_failures = [var.vpc]
}

run "contract_tiers_required_existing_mode" {
  command = plan

  variables {
    vpc = null
    existing = {
      vpc_id = "vpc-0aaaaaaaaaaaaaaaa"
      subnet_ids = {
        public = ["subnet-0pub1", "subnet-0pub2"]
        app    = ["subnet-0app1", "subnet-0app2"]
      }
    }
  }

  expect_failures = [var.existing]
}

run "existing_tiers_need_the_same_subnet_count" {
  command = plan

  variables {
    vpc = null
    existing = {
      vpc_id = "vpc-0aaaaaaaaaaaaaaaa"
      subnet_ids = {
        public = ["subnet-0pub1", "subnet-0pub2"]
        app    = ["subnet-0app1", "subnet-0app2"]
        data   = ["subnet-0dat1", "subnet-0dat2", "subnet-0dat3"]
      }
    }
  }

  expect_failures = [var.existing]
}

run "services_must_match_containerimage_extra_rejected" {
  command = plan

  variables {
    services = {
      api    = { port = 8080, from_alb = true, data_access = ["db"] }
      worker = { port = 9000, callers = ["api"], data_access = ["db"] }
      batch  = { port = 9100 }
    }
  }

  expect_failures = [terraform_data.services_match_containerimage]
}

run "services_must_match_containerimage_missing_rejected" {
  command = plan

  variables {
    services = {
      api = { port = 8080, from_alb = true, data_access = ["db"] }
    }
  }

  expect_failures = [terraform_data.services_match_containerimage]
}

run "services_matching_containerimage_passes" {
  command = plan

  assert {
    condition     = toset(keys(var.services)) == toset(module.in.lists["services"])
    error_message = "Services equal to the containerimage list must pass the precondition"
  }
}

run "references_must_exist_unknown_caller" {
  command = plan

  variables {
    services = {
      api    = { port = 8080, from_alb = true, data_access = ["db"] }
      worker = { port = 9000, callers = ["ghost"], data_access = ["db"] }
    }
  }

  expect_failures = [var.services]
}

run "references_must_exist_unknown_data_store" {
  command = plan

  variables {
    services = {
      api    = { port = 8080, from_alb = true, data_access = ["cache"] }
      worker = { port = 9000, callers = ["api"] }
    }
  }

  expect_failures = [var.services]
}

run "service_named_like_a_reserved_sg_key_rejected" {
  command = plan

  variables {
    services = {
      db     = { port = 8080, from_alb = true }
      worker = { port = 9000 }
    }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/services"]
    values = { insecure_value = "db,worker" }
  }

  expect_failures = [var.services]
}

run "data_stores_must_contain_db" {
  command = plan

  variables {
    services = {
      api    = { port = 8080, from_alb = true }
      worker = { port = 9000, callers = ["api"] }
    }
    data_stores = {
      cache = { port = 6379 }
    }
  }

  expect_failures = [var.data_stores]
}

run "sg_groups_expand" {
  command = plan

  assert {
    condition     = toset(keys(local.security_groups)) == toset(["alb", "api", "worker", "db", "db_proxy"])
    error_message = "Security groups must be alb, one per service, db and db_proxy"
  }

  assert {
    condition     = toset(keys(module.sg.security_group_ids)) == toset(["alb", "api", "worker", "db", "db_proxy"])
    error_message = "The security-group module must create exactly those groups"
  }

  assert {
    condition     = local.security_groups["api"].name == "alpha-dev-api" && local.security_groups["db_proxy"].name == "alpha-dev-db-proxy"
    error_message = "Security group names must be <name_prefix>-<name>"
  }
}

run "proxy_sg_created_without_proxy" {
  command = plan

  variables {
    data_stores = { db = { port = 5432, proxy = false } }
  }

  assert {
    condition     = contains(keys(local.security_groups), "db_proxy") && contains(keys(local.published_strings), "sg_db_proxy_id")
    error_message = "The Proxy security group must exist and be published even when no Proxy is used"
  }
}

run "sg_rules_expand_from_services" {
  command = plan

  variables {
    services = {
      api    = { port = 8080, from_alb = true, data_access = ["db"] }
      worker = { port = 9000, callers = ["api"] }
    }
    data_stores = { db = { port = 5432, proxy = false } }
  }

  assert {
    condition = toset(keys(local.sg_rules)) == toset([
      "alb_in_443_cidr_0_0_0_0_0",
      "alb_in_80_cidr_0_0_0_0_0",
      "alb_out_api",
      "api_in_alb",
      "api_out_worker",
      "worker_in_api",
      "api_out_https",
      "worker_out_https",
      "api_out_db",
      "db_in_api",
    ])
    error_message = "Rules must be exactly the expansion of the rule table (10 rules for this input)"
  }

  assert {
    condition = (
      local.sg_rules["api_in_alb"].type == "ingress" && local.sg_rules["api_in_alb"].security_group == "api" &&
      local.sg_rules["api_in_alb"].peer_group == "alb" && local.sg_rules["api_in_alb"].from_port == 8080
    )
    error_message = "api must accept its service port from the ALB group"
  }

  assert {
    condition = (
      local.sg_rules["alb_out_api"].type == "egress" && local.sg_rules["alb_out_api"].security_group == "alb" &&
      local.sg_rules["alb_out_api"].peer_group == "api" && local.sg_rules["alb_out_api"].from_port == 8080
    )
    error_message = "The ALB must reach api on the api port only"
  }

  assert {
    condition = (
      local.sg_rules["worker_in_api"].type == "ingress" && local.sg_rules["worker_in_api"].security_group == "worker" &&
      local.sg_rules["worker_in_api"].peer_group == "api" && local.sg_rules["worker_in_api"].from_port == 9000
    )
    error_message = "worker must accept its port from its caller api"
  }

  assert {
    condition = (
      local.sg_rules["api_out_worker"].type == "egress" && local.sg_rules["api_out_worker"].peer_group == "worker" &&
      local.sg_rules["api_out_worker"].from_port == 9000
    )
    error_message = "The caller needs the matching egress rule because security group egress is not open by default"
  }
}

run "service_egress_443_only" {
  command = plan

  assert {
    condition = (
      length([for r in values(local.sg_rules) : r if r.type == "egress" && r.peer_group == null]) == 2 &&
      alltrue([for r in values(local.sg_rules) : r.from_port == 443 && r.cidr_ipv4 == "0.0.0.0/0" if r.type == "egress" && r.peer_group == null])
    )
    error_message = "Each service must have one egress rule to 0.0.0.0/0 on 443 and no other egress to a CIDR"
  }

  assert {
    condition     = alltrue([for k in ["api", "worker"] : local.sg_rules["${k}_out_https"].security_group == k])
    error_message = "The HTTPS egress rule must belong to its own service"
  }
}

run "db_rules_with_proxy" {
  command = plan

  assert {
    condition = (
      contains(keys(local.sg_rules), "api_out_db_proxy") && contains(keys(local.sg_rules), "db_proxy_in_api") &&
      contains(keys(local.sg_rules), "worker_out_db_proxy") && contains(keys(local.sg_rules), "db_proxy_in_worker") &&
      contains(keys(local.sg_rules), "db_proxy_out_db") && contains(keys(local.sg_rules), "db_in_db_proxy")
    )
    error_message = "With a Proxy: services reach the Proxy and the Proxy reaches the database"
  }

  assert {
    condition     = alltrue([for r in values(local.sg_rules) : r.peer_group != "api" && r.peer_group != "worker" if r.security_group == "db"])
    error_message = "With a Proxy no service may reach the database directly"
  }

  assert {
    condition     = !contains(keys(local.sg_rules), "api_out_db") && !contains(keys(local.sg_rules), "db_in_api")
    error_message = "No direct service to database rule may exist with a Proxy"
  }
}

run "db_rules_without_proxy" {
  command = plan

  variables {
    data_stores = { db = { port = 5432, proxy = false } }
  }

  assert {
    condition = (
      contains(keys(local.sg_rules), "api_out_db") && contains(keys(local.sg_rules), "db_in_api") &&
      contains(keys(local.sg_rules), "worker_out_db") && contains(keys(local.sg_rules), "db_in_worker")
    )
    error_message = "Without a Proxy services must reach the database directly"
  }

  assert {
    condition     = length([for r in values(local.sg_rules) : r if r.security_group == "db_proxy" || r.peer_group == "db_proxy"]) == 0
    error_message = "Without a Proxy the Proxy security group must have no rules"
  }
}

run "http_only_rejects_public_ipv4" {
  command = plan

  variables {
    alb_ingress = { https = false, cidrs = ["0.0.0.0/0"] }
  }

  expect_failures = [var.alb_ingress]
}

run "http_only_rejects_public_ipv6" {
  command = plan

  variables {
    alb_ingress = { https = false, cidrs = ["::/0"] }
  }

  expect_failures = [var.alb_ingress]
}

run "http_only_allows_prefix_list" {
  command = plan

  variables {
    alb_ingress = { https = false, prefix_list_ids = ["pl-58a04531"] }
  }

  assert {
    condition = (
      toset([for k, r in local.sg_rules : r.from_port if r.security_group == "alb" && r.type == "ingress"]) == toset([80]) &&
      alltrue([for r in values(local.sg_rules) : !r.allow_internet])
    )
    error_message = "Without a certificate the ALB must open only port 80 and nothing may be open to the internet"
  }

  assert {
    condition     = local.sg_rules["alb_in_80_pl_pl_58a04531"].prefix_list_id == "pl-58a04531"
    error_message = "The prefix list must be the source of the port 80 rule"
  }
}

run "http_only_allows_specific_cidr" {
  command = plan

  variables {
    alb_ingress = { https = false, cidrs = ["203.0.113.0/24"] }
  }

  assert {
    condition = (
      local.sg_rules["alb_in_80_cidr_203_0_113_0_24"].cidr_ipv4 == "203.0.113.0/24" &&
      !contains(keys(local.sg_rules), "alb_in_443_cidr_203_0_113_0_24") &&
      alltrue([for r in values(local.sg_rules) : !r.allow_internet])
    )
    error_message = "A narrow CIDR must open only port 80 and never set allow_internet"
  }
}

run "ingress_needs_a_source_with_https" {
  command = plan

  variables {
    alb_ingress = { https = true }
  }

  expect_failures = [var.alb_ingress]
}

run "ingress_needs_a_source_without_https" {
  command = plan

  variables {
    alb_ingress = { https = false }
  }

  expect_failures = [var.alb_ingress]
}

run "https_opens_443_and_80" {
  command = plan

  assert {
    condition = (
      toset([for k, r in local.sg_rules : r.from_port if r.security_group == "alb" && r.type == "ingress"]) == toset([443, 80]) &&
      local.sg_rules["alb_in_443_cidr_0_0_0_0_0"].allow_internet && local.sg_rules["alb_in_80_cidr_0_0_0_0_0"].allow_internet
    )
    error_message = "With a certificate the ALB must open 443 and 80, and say explicitly that it is open to the internet"
  }
}

run "https_allows_cloudfront_prefix_list" {
  command = plan

  variables {
    alb_ingress = { https = true, prefix_list_ids = ["pl-58a04531"] }
  }

  assert {
    condition     = local.sg_rules["alb_in_443_pl_pl_58a04531"].prefix_list_id == "pl-58a04531" && local.sg_rules["alb_in_80_pl_pl_58a04531"].prefix_list_id == "pl-58a04531"
    error_message = "A prefix list must work as the source of both ALB rules"
  }
}

run "publishes_decision_points" {
  command = plan

  assert {
    condition     = jsondecode(local.published_strings["alb_https"]) == { enabled = true }
    error_message = "alb_https must follow alb_ingress.https"
  }

  assert {
    condition     = jsondecode(local.published_strings["db_proxy"]) == { enabled = true }
    error_message = "db_proxy must follow data_stores.db.proxy"
  }

  assert {
    condition     = jsondecode(local.published_strings["data_access"]) == { db = ["api", "worker"] }
    error_message = "data_access must list the services that reach each data store"
  }
}

run "decision_points_follow_inputs" {
  command = plan

  variables {
    alb_ingress = { https = false, cidrs = ["203.0.113.0/24"] }
    data_stores = { db = { port = 5432, proxy = false } }
    services = {
      api    = { port = 8080, from_alb = true, data_access = ["db"] }
      worker = { port = 9000, callers = ["api"] }
    }
  }

  assert {
    condition     = jsondecode(local.published_strings["alb_https"]) == { enabled = false } && jsondecode(local.published_strings["db_proxy"]) == { enabled = false }
    error_message = "Both switches must publish false when the inputs say so"
  }

  assert {
    condition     = jsondecode(local.published_strings["data_access"]) == { db = ["api"] }
    error_message = "Only services with data_access must be listed"
  }
}

run "sg_key_name_conversion" {
  command = plan

  variables {
    services = {
      order-api = { port = 8080, from_alb = true }
    }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/services"]
    values = { insecure_value = "order-api" }
  }

  assert {
    condition     = contains(keys(local.published_strings), "sg_order_api_id") && contains(keys(local.security_groups), "order_api")
    error_message = "Service order-api must publish sg_order_api_id and use the group key order_api"
  }

  assert {
    condition     = local.security_groups["order_api"].name == "alpha-dev-order-api"
    error_message = "The group name keeps the hyphen"
  }
}

run "endpoints_in_create_mode" {
  command = plan

  variables {
    interface_endpoints = { services = ["ecr.api", "logs"] }
  }

  override_module {
    target = module.vpc[0]
    outputs = {
      vpc_id          = "vpc-0123456789abcdef0"
      vpc_cidr        = "10.20.0.0/20"
      azs             = ["ap-northeast-1a", "ap-northeast-1c"]
      subnet_ids      = { public = ["subnet-0pub1", "subnet-0pub2"], app = ["subnet-0app1", "subnet-0app2"], data = ["subnet-0dat1", "subnet-0dat2"] }
      subnet_cidrs    = { public = ["10.20.0.0/26", "10.20.0.64/26"], app = ["10.20.1.0/24", "10.20.2.0/24"], data = ["10.20.5.0/27", "10.20.5.32/27"] }
      nat_gateway_ids = ["nat-0123456789abcdef0"]
    }
  }

  assert {
    condition     = local.interface_endpoints.vpc_id == "vpc-0123456789abcdef0"
    error_message = "Create mode must use the VPC id of the vpc module"
  }

  assert {
    condition     = tolist(local.interface_endpoints.allowed_cidrs) == tolist(["10.20.0.0/20"])
    error_message = "Create mode must allow the VPC CIDR"
  }

  assert {
    condition     = tolist(local.interface_endpoints.subnet_ids) == tolist(["subnet-0app1", "subnet-0app2"])
    error_message = "Endpoints must go to the app tier subnets"
  }

  assert {
    condition     = toset(keys(module.vpce.endpoint_ids)) == toset(["ecr.api", "logs"])
    error_message = "One endpoint per requested service"
  }
}

run "endpoints_in_existing_mode" {
  command = plan

  variables {
    interface_endpoints = { services = ["ecr.api", "logs"] }
    vpc                 = null
    existing = {
      vpc_id = "vpc-0aaaaaaaaaaaaaaaa"
      subnet_ids = {
        public = ["subnet-0pub1", "subnet-0pub2"]
        app    = ["subnet-0app1", "subnet-0app2"]
        data   = ["subnet-0dat1", "subnet-0dat2"]
      }
    }
  }

  override_data {
    target = data.aws_vpc.existing[0]
    values = {
      cidr_block           = "10.50.0.0/16"
      enable_dns_support   = true
      enable_dns_hostnames = true
      cidr_block_associations = [
        {
          association_id = "vpc-cidr-assoc-1"
          cidr_block     = "10.50.0.0/16"
          state          = "associated"
        },
        {
          association_id = "vpc-cidr-assoc-2"
          cidr_block     = "100.64.0.0/16"
          state          = "associated"
        },
        {
          association_id = "vpc-cidr-assoc-3"
          cidr_block     = "192.168.0.0/16"
          state          = "disassociated"
        },
      ]
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.0.0/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.0.64/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.1.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.2.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.5.0/27"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.5.32/27"
    }
  }

  assert {
    condition     = local.interface_endpoints.vpc_id == "vpc-0aaaaaaaaaaaaaaaa"
    error_message = "Mode A must use the registered VPC id"
  }

  assert {
    condition     = tolist(local.interface_endpoints.allowed_cidrs) == tolist(["10.50.0.0/16", "100.64.0.0/16"])
    error_message = "Mode A must allow every associated CIDR of the VPC, secondary included, and no disassociated one"
  }

  assert {
    condition     = tolist(local.interface_endpoints.subnet_ids) == tolist(["subnet-0app1", "subnet-0app2"])
    error_message = "Mode A must put the endpoints in the registered app tier subnets"
  }

  assert {
    condition     = toset(keys(module.vpce.endpoint_ids)) == toset(["ecr.api", "logs"])
    error_message = "Mode A must create the endpoints as well"
  }
}

run "endpoints_none_by_default" {
  command = plan

  assert {
    condition     = length(local.interface_endpoints.services) == 0 && length(module.vpce.endpoint_ids) == 0
    error_message = "Without interface_endpoints.services no endpoint may be created"
  }

  assert {
    condition     = !contains(keys(local.published_strings), "sg_vpce_id")
    error_message = "sg_vpce_id must not be published without endpoints"
  }
}

run "interface_endpoints_published_empty_by_default" {
  command = plan

  assert {
    condition     = local.published_strings["interface_endpoints"] == "[]"
    error_message = "Without endpoints the published list must be an empty JSON array, so a reader can tell none from not-yet-applied"
  }
}

run "interface_endpoints_published_sorted" {
  command = plan

  variables {
    interface_endpoints = { services = ["xray", "ecr.dkr", "ecr.api"] }
  }

  override_module {
    target = module.vpce
    outputs = {
      security_group_id = "sg-0123456789abcdef0"
      endpoint_ids      = { "ecr.api" = "vpce-0123456789abcdef0", "ecr.dkr" = "vpce-0123456789abcdef1", xray = "vpce-0123456789abcdef2" }
    }
  }

  assert {
    condition     = jsondecode(local.published_strings["interface_endpoints"]) == ["ecr.api", "ecr.dkr", "xray"]
    error_message = "The published endpoint services must be a sorted JSON array of the requested services"
  }
}

run "vpce_sg_key_from_module" {
  command = plan

  variables {
    interface_endpoints = { services = ["logs"] }
  }

  override_module {
    target = module.vpce
    outputs = {
      security_group_id = "sg-0123456789abcdef0"
      endpoint_ids      = { logs = "vpce-0123456789abcdef0" }
    }
  }

  assert {
    condition     = local.published_strings["sg_vpce_id"] == "sg-0123456789abcdef0"
    error_message = "sg_vpce_id must come from the vpc-interface-endpoints security group"
  }
}

run "interface_tier_missing_rejected" {
  command = plan

  variables {
    interface_endpoints = { services = ["logs"], subnet_tier = "nope" }
  }

  expect_failures = [var.interface_endpoints]
}

run "interface_tier_public_rejected" {
  command = plan

  variables {
    interface_endpoints = { services = ["logs"], subnet_tier = "public" }
  }

  expect_failures = [var.interface_endpoints]
}

run "interface_tier_app_passes" {
  command = plan

  variables {
    interface_endpoints = { services = ["logs"], subnet_tier = "app" }
  }

  assert {
    condition     = var.interface_endpoints.subnet_tier == "app"
    error_message = "The app tier must be accepted"
  }
}

run "interface_tier_isolated_passes" {
  command = plan

  variables {
    interface_endpoints = { services = ["logs"], subnet_tier = "data" }
  }

  assert {
    condition     = var.interface_endpoints.subnet_tier == "data"
    error_message = "An isolated tier must be accepted"
  }
}

run "interface_tier_public_rejected_in_existing_mode" {
  command = plan

  variables {
    interface_endpoints = { services = ["logs"], subnet_tier = "public" }
    vpc                 = null
    existing = {
      vpc_id = "vpc-0aaaaaaaaaaaaaaaa"
      subnet_ids = {
        public = ["subnet-0pub1", "subnet-0pub2"]
        app    = ["subnet-0app1", "subnet-0app2"]
        data   = ["subnet-0dat1", "subnet-0dat2"]
      }
    }
  }

  override_data {
    target = data.aws_vpc.existing[0]
    values = {
      cidr_block           = "10.50.0.0/16"
      enable_dns_support   = true
      enable_dns_hostnames = true
      cidr_block_associations = [
        {
          association_id = "vpc-cidr-assoc-1"
          cidr_block     = "10.50.0.0/16"
          state          = "associated"
        },
      ]
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.0.0/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.0.64/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.1.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.2.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.5.0/27"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.5.32/27"
    }
  }

  expect_failures = [var.interface_endpoints]
}

run "interface_tier_missing_rejected_in_existing_mode" {
  command = plan

  variables {
    interface_endpoints = { services = ["logs"], subnet_tier = "nope" }
    vpc                 = null
    existing = {
      vpc_id = "vpc-0aaaaaaaaaaaaaaaa"
      subnet_ids = {
        public = ["subnet-0pub1", "subnet-0pub2"]
        app    = ["subnet-0app1", "subnet-0app2"]
        data   = ["subnet-0dat1", "subnet-0dat2"]
      }
    }
  }

  override_data {
    target = data.aws_vpc.existing[0]
    values = {
      cidr_block           = "10.50.0.0/16"
      enable_dns_support   = true
      enable_dns_hostnames = true
      cidr_block_associations = [
        {
          association_id = "vpc-cidr-assoc-1"
          cidr_block     = "10.50.0.0/16"
          state          = "associated"
        },
      ]
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.0.0/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.0.64/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.1.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.2.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.5.0/27"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.5.32/27"
    }
  }

  expect_failures = [var.interface_endpoints]
}

run "existing_vpc_needs_dns_support" {
  command = plan

  variables {
    vpc = null
    existing = {
      vpc_id = "vpc-0aaaaaaaaaaaaaaaa"
      subnet_ids = {
        public = ["subnet-0pub1", "subnet-0pub2"]
        app    = ["subnet-0app1", "subnet-0app2"]
        data   = ["subnet-0dat1", "subnet-0dat2"]
      }
    }
  }

  override_data {
    target = data.aws_vpc.existing[0]
    values = {
      cidr_block           = "10.50.0.0/16"
      enable_dns_support   = false
      enable_dns_hostnames = true
      cidr_block_associations = [
        {
          association_id = "vpc-cidr-assoc-1"
          cidr_block     = "10.50.0.0/16"
          state          = "associated"
        },
      ]
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.0.0/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.0.64/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.1.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.2.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.5.0/27"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.5.32/27"
    }
  }

  expect_failures = [terraform_data.existing_vpc_dns]
}

run "existing_vpc_needs_dns_hostnames" {
  command = plan

  variables {
    vpc = null
    existing = {
      vpc_id = "vpc-0aaaaaaaaaaaaaaaa"
      subnet_ids = {
        public = ["subnet-0pub1", "subnet-0pub2"]
        app    = ["subnet-0app1", "subnet-0app2"]
        data   = ["subnet-0dat1", "subnet-0dat2"]
      }
    }
  }

  override_data {
    target = data.aws_vpc.existing[0]
    values = {
      cidr_block           = "10.50.0.0/16"
      enable_dns_support   = true
      enable_dns_hostnames = false
      cidr_block_associations = [
        {
          association_id = "vpc-cidr-assoc-1"
          cidr_block     = "10.50.0.0/16"
          state          = "associated"
        },
      ]
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.0.0/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.0.64/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.1.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.2.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.5.0/27"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.5.32/27"
    }
  }

  expect_failures = [terraform_data.existing_vpc_dns]
}

run "existing_vpc_with_dns_passes" {
  command = plan

  variables {
    vpc = null
    existing = {
      vpc_id = "vpc-0aaaaaaaaaaaaaaaa"
      subnet_ids = {
        public = ["subnet-0pub1", "subnet-0pub2"]
        app    = ["subnet-0app1", "subnet-0app2"]
        data   = ["subnet-0dat1", "subnet-0dat2"]
      }
    }
  }

  override_data {
    target = data.aws_vpc.existing[0]
    values = {
      cidr_block           = "10.50.0.0/16"
      enable_dns_support   = true
      enable_dns_hostnames = true
      cidr_block_associations = [
        {
          association_id = "vpc-cidr-assoc-1"
          cidr_block     = "10.50.0.0/16"
          state          = "associated"
        },
      ]
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.0.0/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.0.64/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.1.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.2.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.5.0/27"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.5.32/27"
    }
  }

  assert {
    condition     = length(terraform_data.existing_vpc_dns) == 1 && local.vpc_id == "vpc-0aaaaaaaaaaaaaaaa"
    error_message = "A VPC with both DNS settings enabled must pass"
  }
}

run "existing_mode_does_not_touch_routing" {
  command = plan

  variables {
    vpc = null
    existing = {
      vpc_id = "vpc-0aaaaaaaaaaaaaaaa"
      subnet_ids = {
        public = ["subnet-0pub1", "subnet-0pub2"]
        app    = ["subnet-0app1", "subnet-0app2"]
        data   = ["subnet-0dat1", "subnet-0dat2"]
      }
    }
  }

  override_data {
    target = data.aws_vpc.existing[0]
    values = {
      cidr_block           = "10.50.0.0/16"
      enable_dns_support   = true
      enable_dns_hostnames = true
      cidr_block_associations = [
        {
          association_id = "vpc-cidr-assoc-1"
          cidr_block     = "10.50.0.0/16"
          state          = "associated"
        },
      ]
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.0.0/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.0.64/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.1.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.2.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.5.0/27"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.5.32/27"
    }
  }

  assert {
    condition     = length(module.vpc) == 0
    error_message = "Mode A must not call the vpc module: no route tables, internet gateway, NAT, gateway endpoints or default security group"
  }
}

run "nat_json_single" {
  command = plan

  override_module {
    target = module.vpc[0]
    outputs = {
      vpc_id          = "vpc-0123456789abcdef0"
      vpc_cidr        = "10.20.0.0/20"
      azs             = ["ap-northeast-1a", "ap-northeast-1c"]
      subnet_ids      = { public = ["subnet-0pub1", "subnet-0pub2"], app = ["subnet-0app1", "subnet-0app2"], data = ["subnet-0dat1", "subnet-0dat2"] }
      subnet_cidrs    = { public = ["10.20.0.0/26", "10.20.0.64/26"], app = ["10.20.1.0/24", "10.20.2.0/24"], data = ["10.20.5.0/27", "10.20.5.32/27"] }
      nat_gateway_ids = ["nat-0123456789abcdef0"]
    }
  }

  assert {
    condition     = jsondecode(local.published_strings["nat"]) == { mode = "single", ids = ["nat-0123456789abcdef0"] }
    error_message = "nat must be {mode, ids} from the vpc module"
  }
}

run "nat_json_none" {
  command = plan

  variables {
    vpc = merge(var.vpc, { nat_mode = "none" })
  }

  override_module {
    target = module.vpc[0]
    outputs = {
      vpc_id          = "vpc-0123456789abcdef0"
      vpc_cidr        = "10.20.0.0/20"
      azs             = ["ap-northeast-1a", "ap-northeast-1c"]
      subnet_ids      = { public = ["subnet-0pub1", "subnet-0pub2"], app = ["subnet-0app1", "subnet-0app2"], data = ["subnet-0dat1", "subnet-0dat2"] }
      subnet_cidrs    = { public = ["10.20.0.0/26", "10.20.0.64/26"], app = ["10.20.1.0/24", "10.20.2.0/24"], data = ["10.20.5.0/27", "10.20.5.32/27"] }
      nat_gateway_ids = []
    }
  }

  assert {
    condition     = jsondecode(local.published_strings["nat"]) == { mode = "none", ids = [] }
    error_message = "nat_mode none must publish an empty ids list"
  }
}

run "nat_json_existing_mode" {
  command = plan

  variables {
    vpc = null
    existing = {
      vpc_id = "vpc-0aaaaaaaaaaaaaaaa"
      subnet_ids = {
        public = ["subnet-0pub1", "subnet-0pub2"]
        app    = ["subnet-0app1", "subnet-0app2"]
        data   = ["subnet-0dat1", "subnet-0dat2"]
      }
    }
  }

  override_data {
    target = data.aws_vpc.existing[0]
    values = {
      cidr_block           = "10.50.0.0/16"
      enable_dns_support   = true
      enable_dns_hostnames = true
      cidr_block_associations = [
        {
          association_id = "vpc-cidr-assoc-1"
          cidr_block     = "10.50.0.0/16"
          state          = "associated"
        },
      ]
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.0.0/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0pub2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.0.64/26"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.1.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0app2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.2.0/24"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat1"]
    values = {
      availability_zone = "ap-northeast-1a"
      cidr_block        = "10.50.5.0/27"
    }
  }

  override_data {
    target = data.aws_subnet.existing["subnet-0dat2"]
    values = {
      availability_zone = "ap-northeast-1c"
      cidr_block        = "10.50.5.32/27"
    }
  }

  assert {
    condition     = jsondecode(local.published_strings["nat"]) == { mode = "external", ids = [] }
    error_message = "A customer VPC must report its NAT as external, with no ids"
  }
}

run "flow_log_to_foundation_bucket" {
  command = plan

  variables {
    vpc = merge(var.vpc, { flow_log = true })
  }

  assert {
    condition     = local.vpc_flow_log.destination_arn == "arn:aws:s3:::alpha-dev-flow-logs-111111111111"
    error_message = "Flow logs must go to the bucket the foundation stack published"
  }
}

run "no_flow_log_by_default" {
  command = plan

  assert {
    condition     = local.vpc_flow_log == null
    error_message = "flow_log = false must pass no flow log to the vpc module"
  }
}

# ---- AgentCore Runtimes: security groups and data access ----

run "agent_runtimes_default_empty" {
  command = plan

  assert {
    condition     = length([for k in keys(local.security_groups) : k if startswith(k, "agent_")]) == 0
    error_message = "Without Runtimes no Runtime security group may exist"
  }

  assert {
    condition     = local.published_strings["agent_data_access"] == "{}" && length([for k in keys(local.published_strings) : k if startswith(k, "sg_agent_")]) == 0
    error_message = "Without Runtimes agent_data_access must be published as {} and no sg_agent_* key may be published"
  }
}

run "agent_sg_rules_expand" {
  command = plan

  variables {
    services = {
      api    = { port = 8080, from_alb = true, data_access = ["db"] }
      worker = { port = 9000, callers = ["api"] }
    }
    data_stores    = { db = { port = 5432, proxy = false } }
    agent_runtimes = { assistant = { data_access = ["db"] }, order-bot = {} }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\",\"order-bot\"]" }
  }

  assert {
    condition = toset(keys(local.sg_rules)) == toset([
      "alb_in_443_cidr_0_0_0_0_0",
      "alb_in_80_cidr_0_0_0_0_0",
      "alb_out_api",
      "api_in_alb",
      "api_out_worker",
      "worker_in_api",
      "api_out_https",
      "worker_out_https",
      "api_out_db",
      "db_in_api",
      "agent_assistant_out_https",
      "agent_order_bot_out_https",
      "agent_assistant_out_db",
      "db_in_agent_assistant",
    ])
    error_message = "Each Runtime must add one 443 egress rule, and a Runtime with data_access the egress and ingress pair to the data store"
  }

  assert {
    condition = (
      local.security_groups["agent_assistant"].name == "alpha-dev-agent-assistant" &&
      local.security_groups["agent_order_bot"].name == "alpha-dev-agent-order-bot"
    )
    error_message = "Each Runtime must get a security group keyed agent_<name> and named <project>-<env>-agent-<name>"
  }

  assert {
    condition = (
      local.sg_rules["agent_assistant_out_https"].type == "egress" && local.sg_rules["agent_assistant_out_https"].from_port == 443 &&
      local.sg_rules["agent_assistant_out_https"].cidr_ipv4 == "0.0.0.0/0" && local.sg_rules["agent_assistant_out_https"].allow_internet == false
    )
    error_message = "The Runtime egress must be 443 to 0.0.0.0/0 for AWS APIs"
  }

  assert {
    condition     = length([for r in values(local.sg_rules) : r if r.type == "ingress" && startswith(r.security_group, "agent_")]) == 0
    error_message = "A Runtime security group must have no ingress rule"
  }

  assert {
    condition     = jsondecode(local.published_strings["agent_data_access"]) == { db = ["assistant"] }
    error_message = "agent_data_access must list the Runtimes that reach each data store"
  }

  assert {
    condition     = jsondecode(local.published_strings["data_access"]) == { db = ["api"] }
    error_message = "Runtimes must not be mixed into data_access, which lists services only"
  }

  assert {
    condition     = contains(keys(local.published_strings), "sg_agent_assistant_id") && contains(keys(local.published_strings), "sg_agent_order_bot_id")
    error_message = "Each Runtime must publish sg_agent_<name>_id with hyphens turned into underscores"
  }
}

run "agent_data_access_through_proxy" {
  command = plan

  variables {
    agent_runtimes = { assistant = { data_access = ["db"] } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  assert {
    condition = (
      local.sg_rules["agent_assistant_out_db_proxy"].peer_group == "db_proxy" &&
      local.sg_rules["db_proxy_in_agent_assistant"].from_port == 5432 &&
      !contains(keys(local.sg_rules), "agent_assistant_out_db")
    )
    error_message = "With a Proxy the Runtime must reach the Proxy, never the database directly"
  }
}

run "publishes_agent_data_access" {
  command = plan

  assert {
    condition     = jsondecode(local.published_strings["agent_data_access"]) == {}
    error_message = "agent_data_access must be published as {} by default"
  }
}

run "agent_runtimes_must_match_containerimage_extra_rejected" {
  command = plan

  variables {
    agent_runtimes = { assistant = {} }
  }

  expect_failures = [terraform_data.agent_runtimes_match_containerimage]
}

run "agent_runtimes_must_match_containerimage_missing_rejected" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  expect_failures = [terraform_data.agent_runtimes_match_containerimage]
}

run "agent_runtimes_matching_containerimage_passes" {
  command = plan

  variables {
    agent_runtimes = { assistant = {} }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  assert {
    condition     = contains(keys(local.security_groups), "agent_assistant")
    error_message = "Runtime keys equal to containerimage/agent_runtimes must pass"
  }
}

run "agent_data_access_unknown_store_rejected" {
  command = plan

  variables {
    agent_runtimes = { assistant = { data_access = ["cache"] } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  expect_failures = [var.agent_runtimes]
}

run "agent_sg_key_clash_with_service_rejected" {
  command = plan

  variables {
    services = {
      api       = { port = 8080, from_alb = true }
      worker    = { port = 9000 }
      agent-bot = { port = 7000 }
    }
    agent_runtimes = { bot = {} }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/services"]
    values = { insecure_value = "api,worker,agent-bot" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"bot\"]" }
  }

  expect_failures = [var.agent_runtimes]
}

run "control_plane_endpoint_rejected" {
  command = plan

  variables {
    interface_endpoints = { services = ["bedrock-runtime", "bedrock-agentcore-control"] }
  }

  expect_failures = [var.interface_endpoints]
}

run "data_plane_endpoint_passes" {
  command = plan

  variables {
    interface_endpoints = { services = ["bedrock-runtime", "bedrock-agentcore"] }
  }

  assert {
    condition     = jsondecode(local.published_strings["interface_endpoints"]) == ["bedrock-agentcore", "bedrock-runtime"]
    error_message = "bedrock-agentcore must be accepted and published"
  }
}

# ---- common.tf and providers.tf guards: the same runs in every stack ----

run "env_format_uppercase_rejected" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "env_format_too_short_rejected" {
  command = plan

  variables {
    env = "d"
  }

  expect_failures = [var.env]
}

run "env_format_valid_passes" {
  command = plan

  variables {
    env = "dev"
  }

  assert {
    condition     = local.name_prefix == "alpha-dev" && local.ssm_prefix == "/alpha/dev"
    error_message = "A valid env must produce the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Alpha"
  }

  expect_failures = [var.project]
}

run "account_must_match_env" {
  command = plan

  variables {
    env                 = "dev"
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "account_unknown_env_rejected" {
  command = plan

  variables {
    env                 = "staging"
    expected_account_id = "111111111111"
  }

  expect_failures = [var.expected_account_id]
}

run "account_matching_env_passes" {
  command = plan

  variables {
    env                 = "prod"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "alpha-prod" && contains(local.accounts_by_env["prod"], var.expected_account_id)
    error_message = "A prod account with env prod must pass"
  }
}

run "account_is_required" {
  command = plan

  variables {
    expected_account_id = null
  }

  expect_failures = [var.expected_account_id]
}

# A default would let a missing tfvars file point at some account silently.
run "account_has_no_default" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"expected_account_id\" \\{[^}]*\\n\\s*default\\s*=", file("${path.module}/common.tf"))) == 0
    error_message = "expected_account_id must not have a default value"
  }
}

run "deploy_role_in_other_account_rejected" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "deploy_role_in_expected_account_passes" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "A role in the expected account must pass"
  }
}
