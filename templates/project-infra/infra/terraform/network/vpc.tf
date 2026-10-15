locals {
  create_vpc = var.vpc != null

  vpc_flow_log = try(var.vpc.flow_log, false) ? { destination_arn = module.in.strings["flow_log_bucket_arn"] } : null
}

module "vpc" {
  source = "../../../../../modules/vpc"
  count  = local.create_vpc ? 1 : 0

  name     = local.name_prefix
  cidr     = var.vpc.cidr
  azs      = var.vpc.azs
  subnets  = var.vpc.subnets
  nat_mode = var.vpc.nat_mode
  flow_log = local.vpc_flow_log
}
