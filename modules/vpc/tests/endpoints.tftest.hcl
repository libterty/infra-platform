mock_provider "aws" {}

variables {
  name     = "alpha-dev"
  cidr     = "10.0.0.0/20"
  azs      = ["ap-northeast-1a", "ap-northeast-1c"]
  nat_mode = "none"
  subnets = {
    public = { type = "public", newbits = 4, netnum_base = 0 }
    app    = { type = "private", newbits = 4, netnum_base = 4 }
    data   = { type = "isolated", newbits = 4, netnum_base = 8 }
  }
}

run "s3_gateway_by_default" {
  command = apply

  assert {
    condition     = toset(keys(aws_vpc_endpoint.gateway)) == toset(["s3"])
    error_message = "Only the s3 gateway endpoint is created by default"
  }

  assert {
    condition = toset(aws_vpc_endpoint.gateway["s3"].route_table_ids) == toset([
      for k in ["app/ap-northeast-1a", "app/ap-northeast-1c", "data/ap-northeast-1a", "data/ap-northeast-1c"] : aws_route_table.this[k].id
    ])
    error_message = "Gateway endpoint must attach to exactly the private and isolated route tables"
  }

  assert {
    condition     = aws_vpc_endpoint.gateway["s3"].vpc_endpoint_type == "Gateway"
    error_message = "Endpoint type must be Gateway"
  }
}

run "gateway_endpoint_ec2_fails" {
  command = plan

  variables {
    gateway_endpoints = ["ec2"]
  }

  expect_failures = [var.gateway_endpoints]
}

run "gateway_endpoint_s3_and_dynamodb_pass" {
  command = plan

  variables {
    gateway_endpoints = ["s3", "dynamodb"]
  }

  assert {
    condition     = length(aws_vpc_endpoint.gateway) == 2
    error_message = "s3 and dynamodb must both be created"
  }
}

run "no_interface_endpoints_by_default" {
  command = apply

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 0 && length(aws_security_group.vpce) == 0 && length(aws_vpc_security_group_ingress_rule.vpce_https) == 0
    error_message = "interface_endpoints = null must create no endpoint, SG or rule"
  }

  assert {
    condition     = output.vpce_security_group_id == null
    error_message = "vpce_security_group_id must be null"
  }
}

run "interface_endpoints_in_tier" {
  command = apply

  variables {
    interface_endpoints = {
      services    = ["ecr.api", "logs"]
      subnet_tier = "app"
    }
  }

  assert {
    condition     = toset(keys(aws_vpc_endpoint.interface)) == toset(["ecr.api", "logs"])
    error_message = "One endpoint per service"
  }

  assert {
    condition = alltrue([
      for e in values(aws_vpc_endpoint.interface) :
      e.private_dns_enabled == true && e.vpc_endpoint_type == "Interface" &&
      toset(e.subnet_ids) == toset([aws_subnet.this["app/ap-northeast-1a"].id, aws_subnet.this["app/ap-northeast-1c"].id]) &&
      toset(e.security_group_ids) == toset([aws_security_group.vpce[0].id])
    ])
    error_message = "Endpoints need private DNS, the app tier subnets and the vpce SG"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.vpce_https[0].cidr_ipv4 == "10.0.0.0/20" && aws_vpc_security_group_ingress_rule.vpce_https[0].from_port == 443 && aws_vpc_security_group_ingress_rule.vpce_https[0].to_port == 443 && aws_vpc_security_group_ingress_rule.vpce_https[0].ip_protocol == "tcp"
    error_message = "The only ingress rule is 443/tcp from the VPC CIDR"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.vpce_https) == 1 && output.vpce_security_group_id == aws_security_group.vpce[0].id
    error_message = "One ingress rule, and the SG id must be exposed"
  }
}

run "interface_tier_missing_fails" {
  command = plan

  variables {
    interface_endpoints = {
      services    = ["logs"]
      subnet_tier = "nope"
    }
  }

  expect_failures = [aws_vpc.this]
}

run "interface_tier_public_fails" {
  command = plan

  variables {
    interface_endpoints = {
      services    = ["logs"]
      subnet_tier = "public"
    }
  }

  expect_failures = [aws_vpc.this]
}

run "interface_tier_isolated_passes" {
  command = plan

  variables {
    interface_endpoints = {
      services    = ["logs"]
      subnet_tier = "data"
    }
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 1
    error_message = "An isolated tier is a valid interface endpoint tier"
  }
}

run "interface_service_with_region_prefix_fails" {
  command = plan

  variables {
    interface_endpoints = {
      services    = ["com.amazonaws.ap-northeast-1.logs"]
      subnet_tier = "app"
    }
  }

  expect_failures = [var.interface_endpoints]
}

run "interface_service_short_name_passes" {
  command = plan

  variables {
    interface_endpoints = {
      services    = ["ecr.api"]
      subnet_tier = "app"
    }
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 1
    error_message = "ecr.api is a valid service name"
  }
}

run "no_flow_log_by_default" {
  command = plan

  assert {
    condition     = length(aws_flow_log.this) == 0
    error_message = "flow_log = null must create no flow log"
  }
}

run "flow_log_to_s3" {
  command = plan

  variables {
    flow_log = { destination_arn = "arn:aws:s3:::alpha-flow-logs/alpha-dev" }
  }

  assert {
    condition     = length(aws_flow_log.this) == 1 && aws_flow_log.this[0].log_destination_type == "s3" && aws_flow_log.this[0].traffic_type == "ALL"
    error_message = "Flow log must go to S3 and default to ALL traffic"
  }

  assert {
    condition     = aws_flow_log.this[0].log_destination == "arn:aws:s3:::alpha-flow-logs/alpha-dev" && aws_flow_log.this[0].iam_role_arn == null
    error_message = "Flow log must use the given ARN and no IAM role"
  }
}

run "flow_log_cloudwatch_arn_fails" {
  command = plan

  variables {
    flow_log = { destination_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:x" }
  }

  expect_failures = [var.flow_log]
}

run "flow_log_bad_traffic_type_fails" {
  command = plan

  variables {
    flow_log = { destination_arn = "arn:aws:s3:::alpha-flow-logs", traffic_type = "SOME" }
  }

  expect_failures = [var.flow_log]
}

run "flow_log_accept_passes" {
  command = plan

  variables {
    flow_log = { destination_arn = "arn:aws:s3:::alpha-flow-logs", traffic_type = "ACCEPT" }
  }

  assert {
    condition     = aws_flow_log.this[0].traffic_type == "ACCEPT"
    error_message = "ACCEPT is a valid traffic_type"
  }
}
