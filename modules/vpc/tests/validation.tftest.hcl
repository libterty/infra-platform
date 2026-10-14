mock_provider "aws" {}

variables {
  name     = "alpha-dev"
  cidr     = "10.0.0.0/20"
  azs      = ["ap-northeast-1a", "ap-northeast-1c"]
  nat_mode = "none"
  subnets = {
    app = { type = "private", newbits = 4, netnum_base = 4 }
  }
}

run "name_uppercase_fails" {
  command = plan
  variables { name = "Alpha" }
  expect_failures = [var.name]
}

run "name_too_long_fails" {
  command = plan
  variables { name = "a${format("%48s", "")}" }
  expect_failures = [var.name]
}

run "name_two_chars_passes" {
  command = plan
  variables { name = "ab" }
  assert {
    condition     = aws_vpc.this.tags["Name"] == "ab"
    error_message = "A 2 char name must pass and become the Name tag"
  }
}

run "name_48_chars_passes" {
  command = plan
  variables { name = "a${replace(format("%47s", ""), " ", "b")}" }
  assert {
    condition     = length(aws_vpc.this.tags["Name"]) == 48
    error_message = "A 48 char name must pass"
  }
}

run "cidr_slash_15_fails" {
  command = plan
  variables { cidr = "10.0.0.0/15" }
  expect_failures = [var.cidr]
}

run "cidr_slash_25_fails" {
  command = plan
  variables { cidr = "10.0.0.0/25" }
  expect_failures = [var.cidr]
}

run "cidr_host_address_fails" {
  command = plan
  variables { cidr = "10.0.0.1/20" }
  expect_failures = [var.cidr]
}

run "cidr_slash_16_passes" {
  command = plan
  variables {
    cidr = "10.0.0.0/16"
  }
  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16"
    error_message = "/16 must pass"
  }
}

run "cidr_slash_24_passes" {
  command = plan
  variables {
    cidr    = "10.0.0.0/24"
    subnets = { app = { type = "private", newbits = 2, netnum_base = 2 } }
  }
  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/24"
    error_message = "/24 must pass"
  }
}

run "az_count_one_fails" {
  command = plan
  variables { azs = ["ap-northeast-1a"] }
  expect_failures = [var.azs]
}

run "az_count_five_fails" {
  command = plan
  variables {
    azs = ["a", "b", "c", "d", "e"]
  }
  expect_failures = [var.azs]
}

run "az_count_two_passes" {
  command = plan
  assert {
    condition     = length(aws_subnet.this) == 2
    error_message = "2 azs must pass"
  }
}

run "az_count_four_passes" {
  command = plan
  variables {
    azs = ["ap-northeast-1a", "ap-northeast-1b", "ap-northeast-1c", "ap-northeast-1d"]
  }
  assert {
    condition     = length(aws_subnet.this) == 4
    error_message = "4 azs must pass"
  }
}

run "rejects_duplicate_az" {
  command = plan
  variables { azs = ["ap-northeast-1a", "ap-northeast-1a"] }
  expect_failures = [var.azs]
}

run "tier_name_with_dash_and_caps_fails" {
  command = plan
  variables {
    subnets = { "App-Tier" = { type = "private", newbits = 4, netnum_base = 4 } }
  }
  expect_failures = [var.subnets]
}

run "tier_name_snake_case_passes" {
  command = plan
  variables {
    subnets = {
      app    = { type = "private", newbits = 4, netnum_base = 4 }
      data_2 = { type = "isolated", newbits = 4, netnum_base = 8 }
    }
  }
  assert {
    condition     = length(aws_subnet.this) == 4
    error_message = "app and data_2 are valid tier names"
  }
}

run "tier_type_dmz_fails" {
  command = plan
  variables {
    subnets = { app = { type = "dmz", newbits = 4, netnum_base = 4 } }
  }
  expect_failures = [var.subnets]
}

run "two_public_tiers_fail" {
  command = plan
  variables {
    subnets = {
      pub_a = { type = "public", newbits = 4, netnum_base = 0 }
      pub_b = { type = "public", newbits = 4, netnum_base = 4 }
    }
  }
  expect_failures = [var.subnets]
}

run "one_public_tier_passes" {
  command = plan
  variables {
    nat_mode = "single"
    subnets = {
      public = { type = "public", newbits = 4, netnum_base = 0 }
      app    = { type = "private", newbits = 4, netnum_base = 4 }
    }
  }
  assert {
    condition     = length(aws_internet_gateway.this) == 1
    error_message = "One public tier must pass"
  }
}

run "explicit_cidr_invalid_fails" {
  command = plan
  variables {
    subnets = { app = { type = "private", cidrs = { "ap-northeast-1a" = "10.0.4.0/33", "ap-northeast-1c" = "10.0.5.0/24" } } }
  }
  expect_failures = [var.subnets]
}
