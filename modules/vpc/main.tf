resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition     = length(local.tiers_cidrs_azs_mismatch) == 0
      error_message = "cidrs must have exactly one entry per az in azs; mismatch in tiers: ${join(", ", local.tiers_cidrs_azs_mismatch)}."
    }
    precondition {
      condition     = length(local.tiers_newbits_invalid) == 0
      error_message = "newbits must be >= 1, netnum_base >= 0 and the resulting subnet no smaller than /28; invalid tiers: ${join(", ", local.tiers_newbits_invalid)}."
    }
    precondition {
      condition     = length(local.tiers_slots_exhausted) == 0
      error_message = "netnum_base + number of azs exceeds 2^newbits (not enough slots); tiers: ${join(", ", local.tiers_slots_exhausted)}."
    }
    precondition {
      condition     = var.nat_mode == "none" || local.has_public
      error_message = "nat_mode ${var.nat_mode} needs a public tier to place the NAT gateway in."
    }
    precondition {
      condition = var.interface_endpoints == null ? true : (
        contains(keys(var.subnets), var.interface_endpoints.subnet_tier) &&
        try(var.subnets[var.interface_endpoints.subnet_tier].type != "public", false)
      )
      error_message = "interface_endpoints.subnet_tier must be an existing tier that is not public."
    }
    precondition {
      condition     = length(local.outside_vpc) == 0
      error_message = "Subnets outside the VPC CIDR ${var.cidr}: ${join(", ", local.outside_vpc)}."
    }
    precondition {
      condition     = length(local.overlapping_pairs) == 0
      error_message = "Subnet CIDRs overlap: ${join("; ", local.overlapping_pairs)}."
    }
  }
}

# 不宣告任何規則，等於清空 default SG，避免資源誤用。
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-default" })
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.value.az
  cidr_block        = each.value.cidr

  tags = merge(var.tags, { Name = "${var.name}-${each.value.tier}-${each.value.az}" })
}

resource "aws_internet_gateway" "this" {
  count = local.has_public ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = var.name })
}
