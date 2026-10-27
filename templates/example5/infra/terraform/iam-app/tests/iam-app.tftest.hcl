mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_firehose_id"]
  values = { insecure_value = "sg-0aaaaaaa00000004" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_app"]
  values = { insecure_value = "subnet-0app1,subnet-0app2" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dat1,subnet-0dat2" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/telemetry_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-dev-telemetry-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/stream_arn"]
  values = { insecure_value = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/example-dev-telemetry" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_firehose_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-firehose" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["search/opensearch_domain_arn"]
  values = { insecure_value = "arn:aws:es:ap-northeast-1:111111111111:domain/example-dev-search" }
}

run "reads_only_earlier_stack_keys" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn           = "foundation/kms_key_arn"
      sg_firehose_id        = "network/sg_firehose_id"
      telemetry_bucket_arn  = "storage/telemetry_bucket_arn"
      stream_arn            = "storage/stream_arn"
      role_firehose_arn     = "iam-base/role_firehose_arn"
      opensearch_domain_arn = "search/opensearch_domain_arn"
      } && local.ssm_input_lists == {
      subnet_ids_app  = "network/subnet_ids_app"
      subnet_ids_data = "network/subnet_ids_data"
    }
    error_message = "iam-app may read only keys that foundation, network, storage, iam-base and search publish (design 7.2)"
  }
}

# The firehose role exists in iam-base (trust only); this stack attaches the policy to it.
run "firehose_policy_is_attached_to_the_iam_base_role" {
  command = plan

  assert {
    condition = (
      length(regexall("(?m)^\\s*role_arn\\s*=\\s*local\\.role_firehose_arn\\s*$", file("${path.module}/firehose-policy.tf"))) == 1 &&
      length(regexall("(?m)^\\s*policies\\s*=\\s*local\\.firehose_policies\\s*$", file("${path.module}/firehose-policy.tf"))) == 1 &&
      local.role_firehose_arn == "arn:aws:iam::111111111111:role/example-dev-firehose"
    )
    error_message = "The iam-role-policy module must attach local.firehose_policies to the role iam-base published"
  }

  assert {
    condition     = keys(local.firehose_policies) == ["delivery"]
    error_message = "There must be exactly one inline policy named delivery"
  }
}

run "firehose_reads_the_single_stream" {
  command = plan

  assert {
    condition = (
      local.firehose_statements["ReadStream"].Resource == ["arn:aws:kinesis:ap-northeast-1:111111111111:stream/example-dev-telemetry"] &&
      toset(local.firehose_statements["ReadStream"].Action) == toset(["kinesis:DescribeStream", "kinesis:DescribeStreamSummary", "kinesis:GetShardIterator", "kinesis:GetRecords", "kinesis:ListShards"])
    )
    error_message = "The Firehose role may read only the one stream published by storage, with the five read actions"
  }
}

run "firehose_writes_only_the_raw_and_errors_prefixes" {
  command = plan

  assert {
    condition = (
      toset(local.firehose_statements["WriteTelemetryObjects"].Resource) == toset(["arn:aws:s3:::example-dev-telemetry-111111111111/raw/*", "arn:aws:s3:::example-dev-telemetry-111111111111/errors/*"]) &&
      toset(local.firehose_statements["WriteTelemetryObjects"].Action) == toset(["s3:AbortMultipartUpload", "s3:GetObject", "s3:PutObject"])
    )
    error_message = "Object access is limited to the raw/ and errors/ prefixes of the telemetry bucket"
  }

  assert {
    condition = (
      local.firehose_statements["ListTelemetryBucket"].Resource == ["arn:aws:s3:::example-dev-telemetry-111111111111"] &&
      toset(local.firehose_statements["ListTelemetryBucket"].Action) == toset(["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"])
    )
    error_message = "Bucket-level actions apply to the telemetry bucket only"
  }

  assert {
    condition = !anytrue([
      for s in jsondecode(local.firehose_policies["delivery"]).Statement : anytrue([for r in s.Resource : r == "arn:aws:s3:::example-dev-telemetry-111111111111/*"])
    ])
    error_message = "The Firehose role must not be able to write the whole telemetry bucket"
  }
}

run "firehose_calls_only_its_domain" {
  command = plan

  assert {
    condition = (
      toset(local.firehose_statements["WriteDomain"].Action) == toset(["es:ESHttpPost", "es:ESHttpPut", "es:ESHttpGet"]) &&
      local.firehose_statements["WriteDomain"].Resource == ["arn:aws:es:ap-northeast-1:111111111111:domain/example-dev-search/*"]
    )
    error_message = "es:ESHttp* applies to the paths of the single domain only"
  }

  assert {
    condition = (
      toset(local.firehose_statements["DescribeDomain"].Action) == toset(["es:DescribeDomain", "es:DescribeDomains", "es:DescribeDomainConfig"]) &&
      toset(local.firehose_statements["DescribeDomain"].Resource) == toset(["arn:aws:es:ap-northeast-1:111111111111:domain/example-dev-search", "arn:aws:es:ap-northeast-1:111111111111:domain/example-dev-search/*"])
    )
    error_message = "Describe actions apply to the domain and its paths only"
  }
}

run "firehose_vpc_network_interface_actions" {
  command = plan

  assert {
    condition = (
      toset(local.firehose_statements["DescribeNetwork"].Action) == toset(["ec2:DescribeVpcs", "ec2:DescribeVpcAttribute", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DescribeNetworkInterfaces"]) &&
      local.firehose_statements["DescribeNetwork"].Resource == ["*"]
    )
    error_message = "The five Describe actions are the only ones with Resource *"
  }

  assert {
    condition = toset(local.firehose_statements["CreateNetworkInterface"].Resource) == toset([
      "arn:aws:ec2:ap-northeast-1:111111111111:network-interface/*",
      "arn:aws:ec2:ap-northeast-1:111111111111:subnet/subnet-0app1",
      "arn:aws:ec2:ap-northeast-1:111111111111:subnet/subnet-0app2",
      "arn:aws:ec2:ap-northeast-1:111111111111:subnet/subnet-0dat1",
      "arn:aws:ec2:ap-northeast-1:111111111111:subnet/subnet-0dat2",
      "arn:aws:ec2:ap-northeast-1:111111111111:security-group/sg-0aaaaaaa00000004",
    ]) && local.firehose_statements["CreateNetworkInterface"].Action == ["ec2:CreateNetworkInterface"]
    error_message = "Network interfaces may be created only in the VPC subnets and with the Firehose security group"
  }

  assert {
    condition = (
      toset(local.firehose_statements["ManageNetworkInterface"].Action) == toset(["ec2:CreateNetworkInterfacePermission", "ec2:DeleteNetworkInterface"]) &&
      local.firehose_statements["ManageNetworkInterface"].Resource == ["arn:aws:ec2:ap-northeast-1:111111111111:network-interface/*"]
    )
    error_message = "Permission and delete actions apply to network interfaces only"
  }
}

run "firehose_kms_and_logs_are_scoped" {
  command = plan

  assert {
    condition = (
      toset(local.firehose_statements["UseSharedKey"].Action) == toset(["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]) &&
      local.firehose_statements["UseSharedKey"].Resource == ["arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"]
    )
    error_message = "KMS use is limited to the shared key"
  }

  assert {
    condition = (
      local.firehose_statements["WriteLogs"].Action == ["logs:PutLogEvents"] &&
      toset(local.firehose_statements["WriteLogs"].Resource) == toset([
        "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/kinesisfirehose/example-dev-*",
        "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/kinesisfirehose/example-dev-*:log-stream:*",
      ])
    )
    error_message = "Log writes are limited to the Firehose log groups of this project and env"
  }
}

run "firehose_has_exactly_these_statements" {
  command = plan

  assert {
    condition     = toset(keys(local.firehose_statements)) == toset(["ReadStream", "WriteTelemetryObjects", "ListTelemetryBucket", "DescribeDomain", "WriteDomain", "DescribeNetwork", "CreateNetworkInterface", "ManageNetworkInterface", "UseSharedKey", "WriteLogs"])
    error_message = "A new statement must come with a test"
  }
}

# Resource "*" is only allowed for actions that cannot be scoped; each one is listed here with the reason.
#   ec2:DescribeVpcs, DescribeVpcAttribute, DescribeSubnets, DescribeSecurityGroups, DescribeNetworkInterfaces:
#   Describe actions do not support resource-level permissions.
run "no_policy_uses_a_bare_wildcard_resource_except_the_allow_list" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for p in values(local.firehose_policies) : [
        for s in jsondecode(p).Statement :
        !contains(s.Resource, "*") || alltrue([for a in s.Action : contains(["ec2:DescribeVpcs", "ec2:DescribeVpcAttribute", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DescribeNetworkInterfaces"], a)])
      ]
    ]))
    error_message = "Only the five ec2 Describe actions may use Resource *"
  }

  assert {
    condition = alltrue(flatten([
      for p in values(local.firehose_policies) : [
        for s in jsondecode(p).Statement : [
          for res in s.Resource : res == "*" || (!startswith(res, "*") && res != "arn:aws:s3:::*" && !can(regex("^arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]*:\\*$", res)))
        ]
      ]
    ]))
    error_message = "Apart from the allow-listed bare wildcard, no Resource may start with a wildcard or be an account-wide wildcard"
  }

  assert {
    condition = alltrue(flatten([
      for p in values(local.firehose_policies) : [
        for s in jsondecode(p).Statement : s.Effect == "Allow" && !contains(s.Action, "*") && alltrue([for a in s.Action : !endswith(a, ":*")])
      ]
    ]))
    error_message = "Statements must be Allow and may not use * or service:* actions"
  }
}

run "sit_follows_env_and_account" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition = (
      local.firehose_statements["WriteLogs"].Resource[0] == "arn:aws:logs:ap-northeast-1:222222222222:log-group:/aws/kinesisfirehose/example-sit-*" &&
      local.firehose_statements["CreateNetworkInterface"].Resource[0] == "arn:aws:ec2:ap-northeast-1:222222222222:network-interface/*"
    )
    error_message = "Names and ARNs must follow the env and account"
  }
}


# Design section 7.2: iam-app only attaches policies and publishes nothing.
run "publishes_nothing_and_creates_no_role" {
  command = plan

  assert {
    condition     = !fileexists("${path.module}/ssm-outputs.tf") && alltrue([for f in fileset(path.module, "*.tf") : !strcontains(file("${path.module}/${f}"), "ssm-publish")])
    error_message = "iam-app must not publish SSM keys"
  }

  assert {
    condition     = alltrue([for f in fileset(path.module, "*.tf") : !strcontains(file("${path.module}/${f}"), "iam-role/aws")])
    error_message = "iam-app creates no roles: every role is in iam-base"
  }
}

# ---- common.tf and providers.tf guards: the same runs in every stack ----

run "env_format_uppercase_rejected" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "env_format_too_short_rejected" {
  command = plan

  variables {
    env = "d"
  }

  expect_failures = [var.env]
}

run "env_format_valid_passes" {
  command = plan

  variables {
    env = "dev"
  }

  assert {
    condition     = local.name_prefix == "example-dev" && local.ssm_prefix == "/example/dev"
    error_message = "A valid env must give the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Example"
  }

  expect_failures = [var.project]
}

run "account_must_match_env" {
  command = plan

  variables {
    env                 = "dev"
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "account_unknown_env_rejected" {
  command = plan

  variables {
    env                 = "staging"
    expected_account_id = "111111111111"
  }

  expect_failures = [var.expected_account_id]
}

run "account_matching_env_passes" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "example-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
    error_message = "A sit account with env sit must pass"
  }
}

run "account_is_required" {
  command = plan

  variables {
    expected_account_id = null
  }

  expect_failures = [var.expected_account_id]
}

# A default would let a missing tfvars file point at some account silently.
run "account_has_no_default" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"expected_account_id\" \\{[^}]*\\n\\s*default\\s*=", file("${path.module}/common.tf"))) == 0
    error_message = "expected_account_id must not have a default value"
  }
}

run "deploy_role_in_other_account_rejected" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "deploy_role_in_expected_account_passes" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "A role in the expected account must pass"
  }
}
