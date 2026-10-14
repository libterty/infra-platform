mock_provider "aws" {}

variables {
  name = "alpha-dev"
  cidr = "10.0.0.0/20"
  azs  = ["ap-northeast-1a", "ap-northeast-1c"]
  subnets = {
    public = { type = "public", newbits = 4, netnum_base = 0 }
    app    = { type = "private", newbits = 4, netnum_base = 4 }
    data   = { type = "isolated", newbits = 4, netnum_base = 8 }
  }
}

run "one_route_table_per_subnet" {
  command = plan

  assert {
    condition     = toset(keys(aws_route_table.this)) == toset(keys(aws_subnet.this)) && length(aws_route_table.this) == 6
    error_message = "Route table keys must equal subnet keys"
  }

  assert {
    condition     = toset(keys(aws_route_table_association.this)) == toset(keys(aws_subnet.this))
    error_message = "Association keys must equal subnet keys"
  }
}

run "public_tier_routes_to_igw" {
  command = plan

  assert {
    condition     = length(aws_internet_gateway.this) == 1
    error_message = "A public tier needs exactly one internet gateway"
  }

  assert {
    condition     = toset(keys(aws_route.public_igw)) == toset(["public/ap-northeast-1a", "public/ap-northeast-1c"])
    error_message = "Every public route table needs a default route, and only those"
  }

  assert {
    condition     = alltrue([for r in values(aws_route.public_igw) : r.destination_cidr_block == "0.0.0.0/0"])
    error_message = "Public routes must be 0.0.0.0/0"
  }
}

run "no_igw_without_public_tier" {
  command = plan

  variables {
    nat_mode = "none"
    subnets = {
      app = { type = "private", newbits = 4, netnum_base = 4 }
    }
  }

  assert {
    condition     = length(aws_internet_gateway.this) == 0 && length(aws_route.public_igw) == 0
    error_message = "Without a public tier there is no IGW and no public route"
  }
}

run "nat_none" {
  command = plan

  variables {
    nat_mode = "none"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_eip.nat) == 0 && length(aws_route.private_nat) == 0
    error_message = "nat_mode none must create no NAT, EIP or private default route"
  }

  assert {
    condition     = length(output.nat_gateway_ids) == 0
    error_message = "nat_gateway_ids must be empty"
  }
}

run "nat_single" {
  command = apply

  variables {
    nat_mode = "single"
  }

  assert {
    condition     = toset(keys(aws_nat_gateway.this)) == toset(["ap-northeast-1a"]) && length(aws_eip.nat) == 1
    error_message = "single must create one NAT and one EIP, in the first az"
  }

  assert {
    condition     = aws_nat_gateway.this["ap-northeast-1a"].subnet_id == aws_subnet.this["public/ap-northeast-1a"].id
    error_message = "The NAT must sit in the public subnet of the first az"
  }

  assert {
    condition = toset(keys(aws_route.private_nat)) == toset(["app/ap-northeast-1a", "app/ap-northeast-1c"]) && alltrue([
      for r in values(aws_route.private_nat) : r.nat_gateway_id == aws_nat_gateway.this["ap-northeast-1a"].id
    ])
    error_message = "Every private route table must point at the single NAT"
  }

  assert {
    condition     = output.nat_gateway_ids == [aws_nat_gateway.this["ap-northeast-1a"].id]
    error_message = "nat_gateway_ids must hold the single NAT"
  }
}

run "nat_per_az" {
  command = apply

  variables {
    nat_mode = "per_az"
  }

  assert {
    condition     = toset(keys(aws_nat_gateway.this)) == toset(var.azs) && length(aws_eip.nat) == 2
    error_message = "per_az must create one NAT and EIP per az"
  }

  assert {
    condition = alltrue([
      for az in var.azs : aws_nat_gateway.this[az].subnet_id == aws_subnet.this["public/${az}"].id
    ])
    error_message = "Each NAT must sit in the public subnet of its own az"
  }

  assert {
    condition = alltrue([
      for az in var.azs : aws_route.private_nat["app/${az}"].nat_gateway_id == aws_nat_gateway.this[az].id
    ])
    error_message = "Each private route table must point at the NAT of its own az"
  }

  assert {
    condition     = output.nat_gateway_ids == [for az in var.azs : aws_nat_gateway.this[az].id]
    error_message = "nat_gateway_ids must follow the order of azs"
  }
}

run "isolated_tier_local_only_nat_none" {
  command = plan

  variables {
    nat_mode = "none"
  }

  assert {
    condition     = length([for k in concat(keys(aws_route.private_nat), keys(aws_route.public_igw)) : k if startswith(k, "data/")]) == 0
    error_message = "Isolated tier route tables must have no aws_route"
  }
}

run "isolated_tier_local_only_nat_single" {
  command = plan

  variables {
    nat_mode = "single"
  }

  assert {
    condition     = length([for k in concat(keys(aws_route.private_nat), keys(aws_route.public_igw)) : k if startswith(k, "data/")]) == 0
    error_message = "Isolated tier route tables must have no aws_route"
  }
}

run "isolated_tier_local_only_nat_per_az" {
  command = plan

  variables {
    nat_mode = "per_az"
  }

  assert {
    condition     = length([for k in concat(keys(aws_route.private_nat), keys(aws_route.public_igw)) : k if startswith(k, "data/")]) == 0
    error_message = "Isolated tier route tables must have no aws_route"
  }
}

run "nat_requires_public_tier_single_fails" {
  command = plan

  variables {
    nat_mode = "single"
    subnets = {
      app = { type = "private", newbits = 4, netnum_base = 4 }
    }
  }

  expect_failures = [aws_vpc.this]
}

run "nat_requires_public_tier_per_az_fails" {
  command = plan

  variables {
    nat_mode = "per_az"
    subnets = {
      app = { type = "private", newbits = 4, netnum_base = 4 }
    }
  }

  expect_failures = [aws_vpc.this]
}

run "nat_none_without_public_tier_passes" {
  command = plan

  variables {
    nat_mode = "none"
    subnets = {
      app = { type = "private", newbits = 4, netnum_base = 4 }
    }
  }

  assert {
    condition     = length(aws_subnet.this) == 2
    error_message = "nat_mode none must not require a public tier"
  }
}

run "nat_mode_dual_fails" {
  command = plan

  variables {
    nat_mode = "dual"
  }

  expect_failures = [var.nat_mode]
}

run "nat_mode_none_passes" {
  command = plan

  variables {
    nat_mode = "none"
  }

  assert {
    condition     = length(aws_subnet.this) == 6
    error_message = "none is a valid nat_mode"
  }
}

run "nat_mode_single_passes" {
  command = plan

  variables {
    nat_mode = "single"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "single is a valid nat_mode"
  }
}

run "nat_mode_per_az_passes" {
  command = plan

  variables {
    nat_mode = "per_az"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 2
    error_message = "per_az is a valid nat_mode"
  }
}
