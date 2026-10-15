# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what foundation and containerimage publish.
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

run "tfvars_build_the_network" {
  command = plan

  assert {
    condition     = length(module.vpc) == 1
    error_message = "The tfvars must describe a VPC to create"
  }

  assert {
    condition     = toset(keys(module.sg.security_group_ids)) == toset(["alb", "api", "worker", "db", "db_proxy"])
    error_message = "The tfvars must produce the security groups of every service and data store"
  }

  assert {
    condition     = length(module.vpce.endpoint_ids) == length(var.interface_endpoints.services)
    error_message = "Every listed interface endpoint service must get an endpoint"
  }
}

run "data_tier_isolated_by_default" {
  command = plan

  assert {
    condition     = var.vpc.subnets["data"].type == "isolated"
    error_message = "The data tier must be isolated: no route to the internet"
  }
}

# Design section 5.11: dev does not use a Proxy, prod does.
run "proxy_switch_follows_the_environment" {
  command = plan

  assert {
    condition     = var.data_stores["db"].proxy == (var.env == "prod")
    error_message = "db_proxy must be false in dev and true in prod"
  }

  assert {
    condition     = jsondecode(local.published_strings["db_proxy"]).enabled == var.data_stores["db"].proxy
    error_message = "The published db_proxy must follow the tfvars"
  }
}

run "alb_exposure_matches_certificate_decision" {
  command = plan

  assert {
    condition     = jsondecode(local.published_strings["alb_https"]).enabled == var.alb_ingress.https
    error_message = "The published alb_https must follow the tfvars"
  }

  assert {
    condition     = var.alb_ingress.https || !contains(var.alb_ingress.cidrs, "0.0.0.0/0")
    error_message = "An ALB without a certificate must not be open to the world"
  }
}

run "published_interface_endpoints_follow_the_input" {
  command = plan

  assert {
    condition     = length(jsondecode(local.published_strings["interface_endpoints"])) == length(var.interface_endpoints.services) && alltrue([for e in var.interface_endpoints.services : contains(jsondecode(local.published_strings["interface_endpoints"]), e)])
    error_message = "The published interface_endpoints must list exactly the requested services"
  }
}
