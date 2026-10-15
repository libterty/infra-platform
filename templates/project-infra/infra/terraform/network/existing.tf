# Mode A: the customer owns the VPC. Routes, internet gateway, NAT, gateway endpoints and the default security
# group are never touched here. The data sources only prove the IDs exist and supply values to publish.
data "aws_vpc" "existing" {
  count = var.existing == null ? 0 : 1

  id = var.existing.vpc_id
}

data "aws_subnet" "existing" {
  for_each = var.existing == null ? toset([]) : toset(flatten(values(var.existing.subnet_ids)))

  id = each.value
}

# private_dns_enabled endpoints cannot resolve without both settings.
resource "terraform_data" "existing_vpc_dns" {
  count = var.existing == null ? 0 : 1

  lifecycle {
    precondition {
      condition     = data.aws_vpc.existing[0].enable_dns_support
      error_message = "The existing VPC must have DNS support enabled for interface endpoints with private DNS."
    }

    precondition {
      condition     = data.aws_vpc.existing[0].enable_dns_hostnames
      error_message = "The existing VPC must have DNS hostnames enabled for interface endpoints with private DNS."
    }
  }
}

locals {
  existing_vpc_id     = var.existing == null ? null : var.existing.vpc_id
  existing_subnet_ids = var.existing == null ? {} : var.existing.subnet_ids

  # The two modes expose the same values; everything below reads these.
  vpc_id = local.create_vpc ? module.vpc[0].vpc_id : local.existing_vpc_id
  # The primary CIDR is the one the endpoints and the contract call vpc_cidr.
  vpc_cidr = local.create_vpc ? module.vpc[0].vpc_cidr : data.aws_vpc.existing[0].cidr_block
  azs      = local.create_vpc ? module.vpc[0].azs : [for id in try(local.existing_subnet_ids["app"], []) : data.aws_subnet.existing[id].availability_zone]

  subnet_ids = local.create_vpc ? module.vpc[0].subnet_ids : local.existing_subnet_ids
  subnet_cidrs = local.create_vpc ? module.vpc[0].subnet_cidrs : {
    for tier, ids in local.existing_subnet_ids : tier => [for id in ids : data.aws_subnet.existing[id].cidr_block]
  }

  # The NAT of a customer VPC is not ours to report.
  nat = local.create_vpc ? { mode = var.vpc.nat_mode, ids = module.vpc[0].nat_gateway_ids } : { mode = "external", ids = [] }
}
