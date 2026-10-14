locals {
  az_index   = { for i, az in var.azs : az => i }
  vpc_prefix = tonumber(split("/", var.cidr)[1])

  # null when it cannot be computed (no slot left, AZ missing from cidrs); the aws_vpc.this precondition reports it.
  subnet_cidr = {
    for tier, t in var.subnets : tier => {
      for az in var.azs : az => try(
        t.cidrs != null ? t.cidrs[az] : cidrsubnet(var.cidr, t.newbits, t.netnum_base + local.az_index[az]),
        null
      )
    }
  }

  subnets = merge([
    for tier, t in var.subnets : {
      for az in var.azs : "${tier}/${az}" => {
        tier = tier
        type = t.type
        az   = az
        cidr = local.subnet_cidr[tier][az]
      }
    }
  ]...)

  public_tiers = [for tier, t in var.subnets : tier if t.type == "public"]
  has_public   = length(local.public_tiers) > 0
  public_tier  = try(local.public_tiers[0], null)

  # CIDRs become [start, end] integer ranges for pairwise overlap checks.
  vpc_start = sum([for i, o in split(".", cidrhost(var.cidr, 0)) : tonumber(o) * pow(256, 3 - i)])
  vpc_end   = local.vpc_start + pow(2, 32 - local.vpc_prefix) - 1

  subnet_starts = {
    for k, s in local.subnets : k => sum([for i, o in split(".", cidrhost(s.cidr, 0)) : tonumber(o) * pow(256, 3 - i)])
    if s.cidr != null
  }
  subnet_ranges = {
    for k, start in local.subnet_starts : k => {
      start = start
      end   = start + pow(2, 32 - tonumber(split("/", local.subnets[k].cidr)[1])) - 1
    }
  }
  range_keys = sort(keys(local.subnet_ranges))

  overlapping_pairs = flatten([
    for i, a in local.range_keys : [
      for j, b in local.range_keys : "${a} (${local.subnets[a].cidr}) and ${b} (${local.subnets[b].cidr})"
      if j > i && !(local.subnet_ranges[a].end < local.subnet_ranges[b].start || local.subnet_ranges[b].end < local.subnet_ranges[a].start)
    ]
  ])
  outside_vpc = [
    for k in local.range_keys : k
    if local.subnet_ranges[k].start < local.vpc_start || local.subnet_ranges[k].end > local.vpc_end
  ]

  # Violation lists for the preconditions; empty means pass.
  tiers_cidrs_azs_mismatch = [for tier, t in var.subnets : tier if t.cidrs != null && toset(keys(t.cidrs)) != toset(var.azs)]
  tiers_newbits_invalid = [
    for tier, t in var.subnets : tier
    if t.cidrs == null ? (t.newbits < 1 || t.netnum_base < 0 || local.vpc_prefix + t.newbits > 28) : false
  ]
  tiers_slots_exhausted = [
    for tier, t in var.subnets : tier
    if t.cidrs == null ? (t.netnum_base + length(var.azs) > pow(2, t.newbits)) : false
  ]

  nat_azs = var.nat_mode == "none" || !local.has_public ? [] : (var.nat_mode == "single" ? [var.azs[0]] : var.azs)

  private_route_table_keys = [for k, s in local.subnets : k if s.type != "public"]
}
