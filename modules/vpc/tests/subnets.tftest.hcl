mock_provider "aws" {}

variables {
  name = "alpha-dev"
  cidr = "10.0.0.0/20"
  azs  = ["ap-northeast-1a", "ap-northeast-1c"]

  # 多數 run 沒有 public tier；nat_mode 保持 none，避免 NAT 的 precondition 讓 negative test 因錯誤原因通過。
  nat_mode = "none"
  subnets = {
    public = { type = "public", newbits = 4, netnum_base = 0 }
    app    = { type = "private", newbits = 4, netnum_base = 4 }
    data   = { type = "isolated", newbits = 4, netnum_base = 8 }
  }
}

run "auto_cidr_two_az" {
  command = plan

  assert {
    condition = toset(keys(aws_subnet.this)) == toset([
      "public/ap-northeast-1a", "public/ap-northeast-1c",
      "app/ap-northeast-1a", "app/ap-northeast-1c",
      "data/ap-northeast-1a", "data/ap-northeast-1c",
    ])
    error_message = "Subnet keys must be <tier>/<az> for every tier and az"
  }

  assert {
    condition = alltrue([
      for tier, t in var.subnets : alltrue([
        for i, az in var.azs :
        aws_subnet.this["${tier}/${az}"].cidr_block == cidrsubnet(var.cidr, t.newbits, t.netnum_base + i)
      ])
    ])
    error_message = "cidr_block must equal cidrsubnet(cidr, newbits, netnum_base + az_index)"
  }

  assert {
    condition     = aws_subnet.this["app/ap-northeast-1c"].availability_zone == "ap-northeast-1c"
    error_message = "Subnet must be placed in the az from its key"
  }
}

run "auto_cidr_three_az" {
  command = plan

  variables {
    azs = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
  }

  assert {
    condition     = length(aws_subnet.this) == 9
    error_message = "3 tiers x 3 azs must give 9 subnets"
  }

  assert {
    condition = alltrue([
      for tier, t in var.subnets : alltrue([
        for i, az in var.azs :
        aws_subnet.this["${tier}/${az}"].cidr_block == cidrsubnet(var.cidr, t.newbits, t.netnum_base + i)
      ])
    ])
    error_message = "cidr_block must equal cidrsubnet(cidr, newbits, netnum_base + az_index)"
  }
}

run "explicit_cidrs" {
  command = plan

  variables {
    subnets = {
      public = { type = "public", cidrs = { "ap-northeast-1a" = "10.0.0.0/24", "ap-northeast-1c" = "10.0.1.0/24" } }
      app    = { type = "private", cidrs = { "ap-northeast-1a" = "10.0.4.0/22", "ap-northeast-1c" = "10.0.8.0/22" } }
    }
  }

  assert {
    condition     = aws_subnet.this["public/ap-northeast-1c"].cidr_block == "10.0.1.0/24"
    error_message = "Explicit cidr must be used as is"
  }

  assert {
    condition     = aws_subnet.this["app/ap-northeast-1a"].cidr_block == "10.0.4.0/22"
    error_message = "Explicit cidr must be used as is (different prefix per tier is allowed)"
  }
}

run "explicit_cidrs_missing_az_fails" {
  command = plan

  variables {
    subnets = {
      app = { type = "private", cidrs = { "ap-northeast-1a" = "10.0.4.0/24" } }
    }
  }

  expect_failures = [aws_vpc.this]
}

run "explicit_cidrs_extra_az_fails" {
  command = plan

  variables {
    subnets = {
      app = { type = "private", cidrs = { "ap-northeast-1a" = "10.0.4.0/24", "ap-northeast-1c" = "10.0.5.0/24", "ap-northeast-1d" = "10.0.6.0/24" } }
    }
  }

  expect_failures = [aws_vpc.this]
}

run "explicit_cidrs_exact_match_passes" {
  command = plan

  variables {
    subnets = {
      app = { type = "private", cidrs = { "ap-northeast-1c" = "10.0.5.0/24", "ap-northeast-1a" = "10.0.4.0/24" } }
    }
  }

  assert {
    condition     = length(aws_subnet.this) == 2
    error_message = "cidrs covering exactly the azs (any order) must pass"
  }
}

run "both_layouts_fails" {
  command = plan

  variables {
    subnets = {
      app = { type = "private", newbits = 4, netnum_base = 4, cidrs = { "ap-northeast-1a" = "10.0.4.0/24", "ap-northeast-1c" = "10.0.5.0/24" } }
    }
  }

  expect_failures = [var.subnets]
}

run "newbits_without_netnum_base_fails" {
  command = plan

  variables {
    subnets = {
      app = { type = "private", newbits = 4 }
    }
  }

  expect_failures = [var.subnets]
}

run "neither_layout_fails" {
  command = plan

  variables {
    subnets = {
      app = { type = "private" }
    }
  }

  expect_failures = [var.subnets]
}

run "netnum_slots_exhausted_fails" {
  command = plan

  variables {
    subnets = {
      app = { type = "private", newbits = 2, netnum_base = 3 }
    }
  }

  expect_failures = [aws_vpc.this]
}

run "netnum_slots_exactly_fit_passes" {
  command = plan

  variables {
    subnets = {
      app = { type = "private", newbits = 2, netnum_base = 2 }
    }
  }

  assert {
    condition     = length(aws_subnet.this) == 2
    error_message = "netnum_base + azs == 2^newbits must pass"
  }
}

run "newbits_too_large_fails" {
  command = plan

  variables {
    subnets = {
      app = { type = "private", newbits = 9, netnum_base = 0 }
    }
  }

  expect_failures = [aws_vpc.this]
}

run "subnet_outside_vpc_fails" {
  command = plan

  variables {
    subnets = {
      app = { type = "private", cidrs = { "ap-northeast-1a" = "10.0.4.0/24", "ap-northeast-1c" = "10.1.0.0/24" } }
    }
  }

  expect_failures = [aws_vpc.this]
}

run "subnet_straddling_vpc_end_fails" {
  command = plan

  variables {
    subnets = {
      app = { type = "private", cidrs = { "ap-northeast-1a" = "10.0.4.0/24", "ap-northeast-1c" = "10.0.8.0/19" } }
    }
  }

  expect_failures = [aws_vpc.this]
}

run "overlap_fails_precondition" {
  command = plan

  variables {
    subnets = {
      app  = { type = "private", cidrs = { "ap-northeast-1a" = "10.0.1.0/24", "ap-northeast-1c" = "10.0.2.0/24" } }
      data = { type = "isolated", cidrs = { "ap-northeast-1a" = "10.0.1.128/25", "ap-northeast-1c" = "10.0.3.0/24" } }
    }
  }

  expect_failures = [aws_vpc.this]
}

run "overlap_contained_in_earlier_tier_fails" {
  command = plan

  variables {
    subnets = {
      app  = { type = "private", cidrs = { "ap-northeast-1a" = "10.0.1.128/25", "ap-northeast-1c" = "10.0.2.0/24" } }
      data = { type = "isolated", cidrs = { "ap-northeast-1a" = "10.0.1.0/24", "ap-northeast-1c" = "10.0.3.0/24" } }
    }
  }

  expect_failures = [aws_vpc.this]
}

run "adjacent_cidrs_pass" {
  command = plan

  variables {
    subnets = {
      app  = { type = "private", cidrs = { "ap-northeast-1a" = "10.0.1.0/25", "ap-northeast-1c" = "10.0.2.0/24" } }
      data = { type = "isolated", cidrs = { "ap-northeast-1a" = "10.0.1.128/25", "ap-northeast-1c" = "10.0.3.0/24" } }
    }
  }

  assert {
    condition     = length(aws_subnet.this) == 4
    error_message = "Adjacent non-overlapping CIDRs must pass"
  }
}

# 重現 project-a infra-v2/terraform/network/subnets-app.tf 的坑：兩種 newbits 從同一個 /16 切，
# 2 個 AZ 剛好填滿相鄰區段，第 3 個 AZ 靜默撞進別的 tier。槽位數檢查擋不住，只有重疊檢查擋得住。
# app：/19 netnum 4、5（128.0–191.255），第 3 個 AZ 為 netnum 6（192.0/19）。
# agent：/20 netnum 12、13（192.0–223.255），槽位 12+3 <= 16 沒有超出。
run "third_az_overlap_two_az_passes" {
  command = plan

  variables {
    cidr = "10.0.0.0/16"
    subnets = {
      app   = { type = "private", newbits = 3, netnum_base = 4 }
      agent = { type = "private", newbits = 4, netnum_base = 12 }
    }
  }

  assert {
    condition     = length(aws_subnet.this) == 4
    error_message = "The layout must be valid with two azs"
  }
}

run "third_az_overlap_fails" {
  command = plan

  variables {
    cidr = "10.0.0.0/16"
    azs  = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
    subnets = {
      app   = { type = "private", newbits = 3, netnum_base = 4 }
      agent = { type = "private", newbits = 4, netnum_base = 12 }
    }
  }

  expect_failures = [aws_vpc.this]
}

# project-a 原本的配置（兩個 /19 各 netnum 4 與 6）第 3 個 AZ 會先被槽位檢查擋下。
run "legacy_layout_third_az_fails" {
  command = plan

  variables {
    cidr = "10.0.0.0/16"
    azs  = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
    subnets = {
      ecs_app   = { type = "private", newbits = 3, netnum_base = 4 }
      agent_app = { type = "private", newbits = 3, netnum_base = 6 }
    }
  }

  expect_failures = [aws_vpc.this]
}

run "add_az_keeps_existing_keys" {
  command = plan

  variables {
    azs = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
  }

  assert {
    condition = alltrue([
      for tier, cidrs in run.auto_cidr_two_az.subnet_cidrs :
      alltrue([for i, c in cidrs : aws_subnet.this["${tier}/${var.azs[i]}"].cidr_block == c])
    ])
    error_message = "Every key from the 2-az layout must still exist with the same cidr after adding an az"
  }

  assert {
    condition = setsubtract(toset(keys(aws_subnet.this)), toset(flatten([
      for tier, cidrs in run.auto_cidr_two_az.subnet_cidrs : [for i, c in cidrs : "${tier}/${var.azs[i]}"]
    ]))) == toset(["public/ap-northeast-1d", "app/ap-northeast-1d", "data/ap-northeast-1d"])
    error_message = "Adding an az must only add <tier>/<new az> keys"
  }
}

# 位置決定槽位：去掉非最後一個 AZ 時，後面 AZ 的 CIDR 會前移，key 不變。
# 要完全不動就改用 cidrs 明確指定，或只從尾端移除 AZ。
run "remove_az_keeps_remaining_keys" {
  command = plan

  variables {
    azs = ["ap-northeast-1a", "ap-northeast-1d"]
  }

  assert {
    condition = toset(keys(aws_subnet.this)) == toset([
      "public/ap-northeast-1a", "public/ap-northeast-1d",
      "app/ap-northeast-1a", "app/ap-northeast-1d",
      "data/ap-northeast-1a", "data/ap-northeast-1d",
    ])
    error_message = "Removing the middle az must keep the keys of the remaining azs"
  }

  assert {
    condition     = aws_subnet.this["app/ap-northeast-1a"].cidr_block == run.auto_cidr_two_az.subnet_cidrs["app"][0]
    error_message = "The first az keeps its cidr"
  }

  assert {
    condition     = aws_subnet.this["app/ap-northeast-1d"].cidr_block == cidrsubnet(var.cidr, 4, 5)
    error_message = "A later az moves to the slot of its new position"
  }
}

run "remove_last_az_keeps_remaining_cidrs" {
  command = plan

  variables {
    azs = ["ap-northeast-1a", "ap-northeast-1c"]
  }

  assert {
    condition = alltrue([
      for tier, cidrs in run.add_az_keeps_existing_keys.subnet_cidrs :
      alltrue([for i, az in var.azs : aws_subnet.this["${tier}/${az}"].cidr_block == cidrs[i]])
    ])
    error_message = "Removing the last az must not change the cidr of the remaining subnets"
  }
}

run "default_sg_is_emptied" {
  command = apply

  assert {
    condition     = length(aws_default_security_group.this.ingress) == 0 && length(aws_default_security_group.this.egress) == 0
    error_message = "Default security group must carry no ingress or egress rules"
  }
}

run "outputs_grouped_by_tier_in_az_order" {
  command = apply

  assert {
    condition     = toset(keys(output.subnet_ids)) == toset(["public", "app", "data"]) && toset(keys(output.subnet_cidrs)) == toset(["public", "app", "data"]) && toset(keys(output.route_table_ids)) == toset(["public", "app", "data"])
    error_message = "Output keys must be the tier names"
  }

  assert {
    condition = alltrue([
      for tier in keys(var.subnets) : alltrue([
        for i, az in var.azs :
        output.subnet_ids[tier][i] == aws_subnet.this["${tier}/${az}"].id &&
        output.subnet_cidrs[tier][i] == aws_subnet.this["${tier}/${az}"].cidr_block &&
        output.route_table_ids[tier][i] == aws_route_table.this["${tier}/${az}"].id
      ])
    ])
    error_message = "Each list must follow the order of azs"
  }

  assert {
    condition     = output.azs == var.azs
    error_message = "azs must be returned unchanged"
  }
}
