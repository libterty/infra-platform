mock_provider "aws" {}

variables {
  name            = "alpha-dev-to-partner"
  vpc_id          = "vpc-0123456789abcdef0"
  vpc_cidr        = "10.10.0.0/16"
  peer_vpc_id     = "vpc-0fedcba9876543210"
  peer_owner_id   = "444444444444"
  route_table_ids = ["rtb-0123456789abcdef0", "rtb-0fedcba9876543210"]
  peer_cidrs      = ["10.250.0.0/16"]
}

run "creates_requester_side_connection" {
  command = plan

  assert {
    condition = (
      aws_vpc_peering_connection.this.vpc_id == "vpc-0123456789abcdef0" &&
      aws_vpc_peering_connection.this.peer_vpc_id == "vpc-0fedcba9876543210" &&
      aws_vpc_peering_connection.this.peer_owner_id == "444444444444"
    )
    error_message = "The connection must link vpc_id to peer_vpc_id in the peer account"
  }

  assert {
    condition     = aws_vpc_peering_connection.this.tags == tomap({ Name = "alpha-dev-to-partner" })
    error_message = "Without tags input the only tag is Name"
  }
}

# Security: the peer account must accept the request itself; the module never accepts on its behalf.
run "auto_accept_is_false" {
  command = plan

  assert {
    condition     = aws_vpc_peering_connection.this.auto_accept == false
    error_message = "auto_accept must be false: the peer side is accepted by its owner"
  }
}

run "auto_accept_stays_false_with_peer_region" {
  command = plan

  variables {
    peer_region = "ap-southeast-1"
  }

  assert {
    condition     = aws_vpc_peering_connection.this.auto_accept == false && aws_vpc_peering_connection.this.peer_region == "ap-southeast-1"
    error_message = "peer_region must pass through and auto_accept must stay false"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_vpc_peering_connection.this.tags == tomap({ Project = "alpha", Name = "alpha-dev-to-partner" })
    error_message = "Input tags must be kept and Name added"
  }
}

# ---- routes ----

run "one_route_per_route_table_and_cidr" {
  command = plan

  variables {
    peer_cidrs = ["10.250.0.0/16", "10.251.0.0/24"]
  }

  assert {
    condition     = length(aws_route.this) == 4
    error_message = "Routes must be route tables x peer cidrs (2 x 2)"
  }

  assert {
    condition     = toset(keys(aws_route.this)) == toset(["0-10.250.0.0/16", "0-10.251.0.0/24", "1-10.250.0.0/16", "1-10.251.0.0/24"])
    error_message = "Route keys must be <route table index>-<cidr>, never the route table id"
  }
}

run "single_route_table_and_cidr_creates_one_route" {
  command = plan

  variables {
    route_table_ids = ["rtb-0123456789abcdef0"]
  }

  assert {
    condition     = length(aws_route.this) == 1
    error_message = "One route table and one cidr must create one route"
  }
}

run "three_route_tables_and_two_cidrs_create_six_routes" {
  command = plan

  variables {
    route_table_ids = ["rtb-0123456789abcdef0", "rtb-0123456789abcdef1", "rtb-0123456789abcdef2"]
    peer_cidrs      = ["10.250.0.0/16", "10.251.0.0/16"]
  }

  assert {
    condition     = length(aws_route.this) == 6
    error_message = "Routes must be route tables x peer cidrs (3 x 2)"
  }
}

run "routes_point_at_the_connection" {
  command = apply

  assert {
    condition     = alltrue([for r in aws_route.this : r.vpc_peering_connection_id == aws_vpc_peering_connection.this.id])
    error_message = "Every route must target the peering connection"
  }

  assert {
    condition     = aws_route.this["1-10.250.0.0/16"].route_table_id == "rtb-0fedcba9876543210" && aws_route.this["1-10.250.0.0/16"].destination_cidr_block == "10.250.0.0/16"
    error_message = "Each route must put the peer cidr into the route table at its index"
  }

  assert {
    condition     = alltrue([for r in aws_route.this : r.destination_cidr_block != "0.0.0.0/0"])
    error_message = "No route may send the default route to the peer"
  }

  assert {
    condition     = output.peering_connection_id == aws_vpc_peering_connection.this.id
    error_message = "peering_connection_id must be the connection id"
  }
}

# Route table IDs that are unknown at plan time must not break for_each.
run "plans_when_route_table_ids_are_unknown" {
  command = plan

  module {
    source = "./tests/fixtures/unknown-ids"
  }

  assert {
    condition     = length(aws_route_table.private) == 2
    error_message = "Plan must succeed (for_each keys must not depend on route table IDs); the real check is that plan does not error"
  }
}

# ---- vpc ids ----

run "rejects_vpc_id_wrong_prefix" {
  command = plan

  variables {
    vpc_id = "subnet-0123456789abcdef0"
  }

  expect_failures = [var.vpc_id]
}

run "rejects_vpc_id_non_hex" {
  command = plan

  variables {
    vpc_id = "vpc-xyz"
  }

  expect_failures = [var.vpc_id]
}

run "accepts_short_vpc_id" {
  command = plan

  variables {
    vpc_id = "vpc-0a1b2c3d"
  }

  assert {
    condition     = aws_vpc_peering_connection.this.vpc_id == "vpc-0a1b2c3d"
    error_message = "An 8-digit vpc id must be accepted"
  }
}

run "rejects_peer_vpc_id_wrong_prefix" {
  command = plan

  variables {
    peer_vpc_id = "rtb-0123456789abcdef0"
  }

  expect_failures = [var.peer_vpc_id]
}

run "accepts_peer_vpc_id" {
  command = plan

  variables {
    peer_vpc_id = "vpc-0a1b2c3d4e5f60718"
  }

  assert {
    condition     = aws_vpc_peering_connection.this.peer_vpc_id == "vpc-0a1b2c3d4e5f60718"
    error_message = "A 17-digit vpc id must be accepted"
  }
}

# ---- peer_owner_id ----

run "rejects_peer_owner_id_11_digits" {
  command = plan

  variables {
    peer_owner_id = "44444444444"
  }

  expect_failures = [var.peer_owner_id]
}

run "rejects_peer_owner_id_13_digits" {
  command = plan

  variables {
    peer_owner_id = "4444444444444"
  }

  expect_failures = [var.peer_owner_id]
}

run "rejects_peer_owner_id_with_letters" {
  command = plan

  variables {
    peer_owner_id = "44444444444a"
  }

  expect_failures = [var.peer_owner_id]
}

run "accepts_peer_owner_id_12_digits" {
  command = plan

  variables {
    peer_owner_id = "444444444444"
  }

  assert {
    condition     = aws_vpc_peering_connection.this.peer_owner_id == "444444444444"
    error_message = "A 12-digit account id must be accepted"
  }
}

# ---- peer_region ----

run "rejects_peer_region_malformed" {
  command = plan

  variables {
    peer_region = "Tokyo"
  }

  expect_failures = [var.peer_region]
}

run "accepts_peer_region" {
  command = plan

  variables {
    peer_region = "us-east-1"
  }

  assert {
    condition     = aws_vpc_peering_connection.this.peer_region == "us-east-1"
    error_message = "A well-formed region must be accepted"
  }
}

# ---- name ----

run "rejects_name_with_uppercase" {
  command = plan

  variables {
    name = "Alpha-dev"
  }

  expect_failures = [var.name]
}

run "accepts_lowercase_name" {
  command = plan

  variables {
    name = "alpha-sit-to-partner"
  }

  assert {
    condition     = aws_vpc_peering_connection.this.tags["Name"] == "alpha-sit-to-partner"
    error_message = "A lowercase name must be accepted"
  }
}

# ---- vpc_cidr ----

run "rejects_vpc_cidr_malformed" {
  command = plan

  variables {
    vpc_cidr = "10.10.0.0"
  }

  expect_failures = [var.vpc_cidr]
}

run "rejects_vpc_cidr_with_host_bits" {
  command = plan

  variables {
    vpc_cidr = "10.10.0.1/16"
  }

  expect_failures = [var.vpc_cidr]
}

run "accepts_vpc_cidr" {
  command = plan

  variables {
    vpc_cidr = "10.20.0.0/20"
  }

  assert {
    condition     = length(aws_route.this) == 2
    error_message = "A valid network address must be accepted"
  }
}

# ---- route_table_ids ----

run "rejects_empty_route_table_ids" {
  command = plan

  variables {
    route_table_ids = []
  }

  expect_failures = [var.route_table_ids]
}

run "rejects_route_table_id_wrong_prefix" {
  command = plan

  variables {
    route_table_ids = ["vpc-0123456789abcdef0"]
  }

  expect_failures = [var.route_table_ids]
}

run "rejects_duplicate_route_table_ids" {
  command = plan

  variables {
    route_table_ids = ["rtb-0123456789abcdef0", "rtb-0123456789abcdef0"]
  }

  expect_failures = [var.route_table_ids]
}

run "accepts_route_table_id" {
  command = plan

  variables {
    route_table_ids = ["rtb-0a1b2c3d"]
  }

  assert {
    condition     = length(aws_route.this) == 1
    error_message = "A well-formed route table id must be accepted"
  }
}

# ---- peer_cidrs ----

run "rejects_default_route_cidr" {
  command = plan

  variables {
    peer_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.peer_cidrs]
}

run "rejects_default_route_cidr_next_to_valid_one" {
  command = plan

  variables {
    peer_cidrs = ["10.250.0.0/16", "0.0.0.0/0"]
  }

  expect_failures = [var.peer_cidrs]
}

run "rejects_empty_peer_cidrs" {
  command = plan

  variables {
    peer_cidrs = []
  }

  expect_failures = [var.peer_cidrs]
}

run "rejects_peer_cidr_malformed" {
  command = plan

  variables {
    peer_cidrs = ["not-a-cidr"]
  }

  expect_failures = [var.peer_cidrs]
}

run "rejects_peer_cidr_with_host_bits" {
  command = plan

  variables {
    peer_cidrs = ["10.250.0.1/16"]
  }

  expect_failures = [var.peer_cidrs]
}

run "rejects_ipv6_peer_cidr" {
  command = plan

  variables {
    peer_cidrs = ["2001:db8::/32"]
  }

  expect_failures = [var.peer_cidrs]
}

run "rejects_duplicate_peer_cidrs" {
  command = plan

  variables {
    peer_cidrs = ["10.250.0.0/16", "10.250.0.0/16"]
  }

  expect_failures = [var.peer_cidrs]
}

run "rejects_peer_cidr_equal_to_vpc_cidr" {
  command = plan

  variables {
    peer_cidrs = ["10.10.0.0/16"]
  }

  expect_failures = [var.peer_cidrs]
}

run "rejects_peer_cidr_inside_vpc_cidr" {
  command = plan

  variables {
    peer_cidrs = ["10.10.5.0/24"]
  }

  expect_failures = [var.peer_cidrs]
}

run "rejects_peer_cidr_that_contains_vpc_cidr" {
  command = plan

  variables {
    peer_cidrs = ["10.0.0.0/8"]
  }

  expect_failures = [var.peer_cidrs]
}

run "rejects_overlap_when_only_one_peer_cidr_overlaps" {
  command = plan

  variables {
    peer_cidrs = ["10.250.0.0/16", "10.10.128.0/17"]
  }

  expect_failures = [var.peer_cidrs]
}

run "accepts_disjoint_peer_cidrs" {
  command = plan

  variables {
    peer_cidrs = ["10.250.0.0/16", "10.11.0.0/16"]
  }

  assert {
    condition     = length(aws_route.this) == 4
    error_message = "CIDRs that do not overlap vpc_cidr must be accepted"
  }
}
