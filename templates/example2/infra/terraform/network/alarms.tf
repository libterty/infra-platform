locals {
  nat_azs = local.no_nat ? [] : var.azs

  nat_alarms = {
    for i, az in local.nat_azs : "nat_${i + 1}_port_allocation_errors" => {
      description = "NAT gateway ${i + 1} (${az}) could not allocate a source port: it is running out of simultaneous connections to one destination. Check which tasks open many connections to a single address."
      threshold   = 10
      # Two periods in a row, so one burst does not page anyone.
      evaluation_periods = 2
      metric = {
        namespace   = "AWS/NATGateway"
        metric_name = "ErrorPortAllocation"
        dimensions  = { NatGatewayId = module.vpc.nat_gateway_ids[i] }
        statistic   = "Sum"
        period      = 300
      }
    }
  }
}

module "nat_alarms" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/metric-alarm/aws"
  version = "~> 0.1.0"

  name_prefix    = local.name_prefix
  alarms         = local.nat_alarms
  sns_topic_arns = [module.in.strings["alarm_topic_arn"]]
}
