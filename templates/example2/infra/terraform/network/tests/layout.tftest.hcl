# Runs the real vpc module (no override) so its overlap and slot preconditions judge the subnet layout of this stack.
mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  vpc_cidr            = "10.10.0.0/16"
  azs                 = ["ap-northeast-1a", "ap-northeast-1c"]
  alb_ingress         = { cidrs = ["203.0.113.0/24"] }
}

override_module {
  target = module.in
  outputs = {
    strings = { alarm_topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms" }
    lists   = {}
  }
}

override_data {
  target = data.aws_prefix_list.s3
  values = { id = "pl-0123456789abcdef0" }
}

run "two_azs_fit_without_overlap" {
  command = plan

  assert {
    condition = module.vpc.subnet_cidrs == {
      public = ["10.10.0.0/24", "10.10.1.0/24"]
      app    = ["10.10.64.0/19", "10.10.96.0/19"]
      agent  = ["10.10.160.0/19", "10.10.192.0/19"]
      db     = ["10.10.10.0/24", "10.10.11.0/24"]
    }
    error_message = "The subnet layout must be public /24, app /19, agent /19, db /24, each tier in its own range"
  }
}

run "three_azs_fit_without_overlap" {
  command = plan

  variables {
    azs = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
  }

  assert {
    condition     = length(flatten(values(module.vpc.subnet_cidrs))) == 12 && length(distinct(flatten(values(module.vpc.subnet_cidrs)))) == 12
    error_message = "Three AZs give twelve distinct subnets; the vpc module rejects overlapping ranges"
  }
}
