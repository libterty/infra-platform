mock_provider "aws" {}

variables {
  name     = "alpha-dev"
  cidr     = "10.0.0.0/20"
  azs      = ["ap-northeast-1a", "ap-northeast-1c"]
  nat_mode = "none"
  tags     = { Env = "dev" }
  subnets = {
    public = { type = "public", newbits = 4, netnum_base = 0 }
    app    = { type = "private", newbits = 4, netnum_base = 4 }
    data   = { type = "isolated", newbits = 4, netnum_base = 8 }
  }
}

run "no_tier_tags_keeps_0_1_0_tags" {
  command = plan

  assert {
    condition = alltrue([
      for k, s in aws_subnet.this :
      s.tags == tomap({ Env = "dev", Name = "alpha-dev-${split("/", k)[0]}-${split("/", k)[1]}" })
    ])
    error_message = "Without tier tags a subnet must carry only var.tags and Name, as in 0.1.0"
  }
}

run "tier_tags_apply_only_to_that_tier" {
  command = plan

  variables {
    subnets = {
      public = { type = "public", newbits = 4, netnum_base = 0, tags = { "kubernetes.io/role/elb" = "1" } }
      app = {
        type = "private", newbits = 4, netnum_base = 4
        tags = { "kubernetes.io/role/internal-elb" = "1", "karpenter.sh/discovery" = "alpha-dev" }
      }
      data = { type = "isolated", newbits = 4, netnum_base = 8 }
    }
  }

  assert {
    condition = alltrue([
      for az in var.azs :
      aws_subnet.this["public/${az}"].tags == tomap({ Env = "dev", Name = "alpha-dev-public-${az}", "kubernetes.io/role/elb" = "1" })
    ])
    error_message = "The public tier must get its own tag plus var.tags and Name"
  }

  assert {
    condition = alltrue([
      for az in var.azs :
      aws_subnet.this["app/${az}"].tags == tomap({
        Env                               = "dev"
        Name                              = "alpha-dev-app-${az}"
        "kubernetes.io/role/internal-elb" = "1"
        "karpenter.sh/discovery"          = "alpha-dev"
      })
    ])
    error_message = "The app tier must get both of its tags plus var.tags and Name"
  }

  # Negative: tags of one tier never leak into another tier.
  assert {
    condition = alltrue([
      for az in var.azs :
      !contains(keys(aws_subnet.this["data/${az}"].tags), "kubernetes.io/role/elb") &&
      !contains(keys(aws_subnet.this["data/${az}"].tags), "karpenter.sh/discovery") &&
      !contains(keys(aws_subnet.this["public/${az}"].tags), "karpenter.sh/discovery")
    ])
    error_message = "Tier tags must not appear on other tiers"
  }

  # Negative: VPC and other resources do not get tier tags.
  assert {
    condition     = !contains(keys(aws_vpc.this.tags), "kubernetes.io/role/elb")
    error_message = "Tier tags must only be applied to subnets"
  }
}

run "tier_tags_override_var_tags" {
  command = plan

  variables {
    subnets = {
      app = { type = "private", newbits = 4, netnum_base = 4, tags = { Env = "sit" } }
    }
  }

  assert {
    condition     = aws_subnet.this["app/ap-northeast-1a"].tags["Env"] == "sit"
    error_message = "Tier tags must be merged after var.tags"
  }
}

run "name_tag_is_not_overridable" {
  command = plan

  variables {
    subnets = {
      app = { type = "private", newbits = 4, netnum_base = 4, tags = { Name = "evil" } }
    }
  }

  expect_failures = [var.subnets]
}

run "name_lookalike_keys_are_allowed" {
  command = plan

  variables {
    subnets = {
      app = { type = "private", newbits = 4, netnum_base = 4, tags = { name = "lower", "Name2" = "x" } }
    }
  }

  assert {
    condition     = aws_subnet.this["app/ap-northeast-1a"].tags["Name"] == "alpha-dev-app-ap-northeast-1a" && aws_subnet.this["app/ap-northeast-1a"].tags["name"] == "lower"
    error_message = "Only the exact key Name is reserved; Name stays the generated value"
  }
}
