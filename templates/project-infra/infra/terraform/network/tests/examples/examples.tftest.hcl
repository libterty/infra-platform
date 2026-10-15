# Run by scripts/validate.sh once per file in envs/examples/ with -var-file, so the examples cannot rot.
# Assertions hold for any valid example; do not set variables here, they would hide the example values.
mock_provider "aws" {}

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

run "interface_endpoint_count_matches_services" {
  command = plan

  assert {
    condition     = length(module.vpce.endpoint_ids) == length(var.interface_endpoints.services)
    error_message = "One endpoint per listed service"
  }
}

run "per_az_nat_has_one_gateway_per_az" {
  command = plan

  assert {
    condition     = var.vpc.nat_mode != "per_az" || length(module.vpc[0].nat_gateway_ids) == length(var.vpc.azs)
    error_message = "nat_mode per_az must create one NAT gateway in every AZ"
  }

  assert {
    condition     = var.vpc.nat_mode != "single" || length(module.vpc[0].nat_gateway_ids) == 1
    error_message = "nat_mode single must create exactly one NAT gateway"
  }
}

run "alb_without_certificate_is_not_open_to_the_world" {
  command = plan

  assert {
    condition     = var.alb_ingress.https || alltrue([for r in values(local.sg_rules) : !(r.security_group == "alb" && r.cidr_ipv4 == "0.0.0.0/0")])
    error_message = "Without a certificate no ALB rule may use 0.0.0.0/0"
  }
}

run "flow_log_points_at_the_foundation_bucket" {
  command = plan

  assert {
    condition     = !var.vpc.flow_log || local.vpc_flow_log.destination_arn == "arn:aws:s3:::alpha-dev-flow-logs-111111111111"
    error_message = "Enabled flow logs must go to the bucket of the foundation stack"
  }
}

run "every_tier_is_published" {
  command = plan

  assert {
    condition = alltrue([
      for t in keys(var.vpc.subnets) :
      contains(keys(local.published_lists), "subnet_ids_${t}") && contains(keys(local.published_lists), "subnet_cidrs_${t}")
    ])
    error_message = "Every tier must publish its subnet IDs and CIDRs"
  }
}

run "contract_tiers_present" {
  command = plan

  assert {
    condition     = alltrue([for t in ["public", "app", "data"] : contains(keys(var.vpc.subnets), t)])
    error_message = "Examples must contain the tiers public, app and data"
  }
}

run "published_interface_endpoints_follow_the_input" {
  command = plan

  assert {
    condition     = length(jsondecode(local.published_strings["interface_endpoints"])) == length(var.interface_endpoints.services) && alltrue([for e in var.interface_endpoints.services : contains(jsondecode(local.published_strings["interface_endpoints"]), e)])
    error_message = "The published interface_endpoints must list exactly the requested services"
  }
}
