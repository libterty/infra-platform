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
  target = module.in.data.aws_ssm_parameter.this["storage/raw_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-dev-raw-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/curated_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-dev-curated-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/athena_results_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-dev-athena-results-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/curated_database_name"]
  values = { insecure_value = "example_dev_curated" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/stream_arn"]
  values = { insecure_value = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/example-dev-events" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_firehose_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-firehose" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["search/opensearch_domain_arn"]
  values = { insecure_value = "arn:aws:es:ap-northeast-1:111111111111:domain/example-dev-search" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["analytics/athena_workgroup_arn"]
  values = { insecure_value = "arn:aws:athena:ap-northeast-1:111111111111:workgroup/example-dev-analytics" }
}

run "reads_only_earlier_stack_keys_of_design_7_2" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn               = "foundation/kms_key_arn"
      sg_firehose_id            = "network/sg_firehose_id"
      raw_bucket_arn            = "storage/raw_bucket_arn"
      curated_bucket_arn        = "storage/curated_bucket_arn"
      athena_results_bucket_arn = "storage/athena_results_bucket_arn"
      curated_database_name     = "storage/curated_database_name"
      stream_arn                = "storage/stream_arn"
      role_firehose_arn         = "iam-base/role_firehose_arn"
      opensearch_domain_arn     = "search/opensearch_domain_arn"
      athena_workgroup_arn      = "analytics/athena_workgroup_arn"
      } && local.ssm_input_lists == {
      subnet_ids_app  = "network/subnet_ids_app"
      subnet_ids_data = "network/subnet_ids_data"
    }
    error_message = "iam-app may read only keys that foundation, network, storage, iam-base, search and analytics publish (design 7.2)"
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
      local.firehose_statements["ReadStream"].Resource == ["arn:aws:kinesis:ap-northeast-1:111111111111:stream/example-dev-events"] &&
      toset(local.firehose_statements["ReadStream"].Action) == toset(["kinesis:DescribeStream", "kinesis:DescribeStreamSummary", "kinesis:GetShardIterator", "kinesis:GetRecords", "kinesis:ListShards"])
    )
    error_message = "The Firehose role may read only the one stream published by storage, with the five read actions"
  }
}

run "firehose_writes_only_raw_and_errors_prefixes" {
  command = plan

  assert {
    condition = (
      toset(local.firehose_statements["WriteRawObjects"].Resource) == toset(["arn:aws:s3:::example-dev-raw-111111111111/raw/*", "arn:aws:s3:::example-dev-raw-111111111111/errors/*"]) &&
      toset(local.firehose_statements["WriteRawObjects"].Action) == toset(["s3:AbortMultipartUpload", "s3:GetObject", "s3:PutObject"])
    )
    error_message = "Object access is limited to the raw/ and errors/ prefixes of the raw bucket"
  }

  assert {
    condition = (
      local.firehose_statements["ListRawBucket"].Resource == ["arn:aws:s3:::example-dev-raw-111111111111"] &&
      toset(local.firehose_statements["ListRawBucket"].Action) == toset(["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"])
    )
    error_message = "Bucket-level actions apply to the raw bucket only"
  }

  assert {
    condition = !anytrue([
      for s in jsondecode(local.firehose_policies["delivery"]).Statement : anytrue([for r in s.Resource : r == "arn:aws:s3:::example-dev-raw-111111111111/*"])
    ])
    error_message = "The Firehose role must not be able to write the whole raw bucket"
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
    condition     = toset(keys(local.firehose_statements)) == toset(["ReadStream", "WriteRawObjects", "ListRawBucket", "DescribeDomain", "WriteDomain", "DescribeNetwork", "CreateNetworkInterface", "ManageNetworkInterface", "UseSharedKey", "WriteLogs"])
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
      for p in concat(values(local.firehose_policies), values(local.quicksight_athena_role.policies)) : [
        for s in jsondecode(p).Statement :
        !contains(s.Resource, "*") || alltrue([for a in s.Action : contains(["ec2:DescribeVpcs", "ec2:DescribeVpcAttribute", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DescribeNetworkInterfaces"], a)])
      ]
    ]))
    error_message = "Only the five ec2 Describe actions may use Resource *"
  }

  assert {
    condition = alltrue(flatten([
      for p in concat(values(local.firehose_policies), values(local.quicksight_athena_role.policies)) : [
        for s in jsondecode(p).Statement : [
          for res in s.Resource : res == "*" || (!startswith(res, "*") && res != "arn:aws:s3:::*" && !can(regex("^arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]*:\\*$", res)))
        ]
      ]
    ]))
    error_message = "Apart from the allow-listed bare wildcard, no Resource may start with a wildcard or be an account-wide wildcard"
  }

  assert {
    condition = alltrue(flatten([
      for p in concat(values(local.firehose_policies), values(local.quicksight_athena_role.policies)) : [
        for s in jsondecode(p).Statement : s.Effect == "Allow" && !contains(s.Action, "*") && alltrue([for a in s.Action : !endswith(a, ":*")])
      ]
    ]))
    error_message = "Statements must be Allow and may not use * or service:* actions"
  }
}

run "quicksight_athena_trusts_quicksight_in_this_account" {
  command = plan

  assert {
    condition = (
      local.quicksight_athena_role.name == "example-dev-quicksight-athena" &&
      toset(local.quicksight_athena_role.trust.service_principals) == toset(["quicksight.amazonaws.com"]) &&
      local.quicksight_athena_role.trust.source_account == "111111111111"
    )
    error_message = "The role must trust quicksight.amazonaws.com with source_account"
  }

  assert {
    condition = (
      length(regexall("(?m)^\\s*name\\s*=\\s*local\\.quicksight_athena_role\\.name\\s*$", file("${path.module}/quicksight-athena.tf"))) == 1 &&
      length(regexall("(?m)^\\s*trust\\s*=\\s*local\\.quicksight_athena_role\\.trust\\s*$", file("${path.module}/quicksight-athena.tf"))) == 1 &&
      length(regexall("(?m)^\\s*inline_policies\\s*=\\s*local\\.quicksight_athena_role\\.policies\\s*$", file("${path.module}/quicksight-athena.tf"))) == 1
    )
    error_message = "The role module call must take name, trust and policies from the role spec"
  }
}

run "quicksight_athena_queries_one_workgroup" {
  command = plan

  assert {
    condition = (
      local.quicksight_athena_statements["QueryWorkgroup"].Resource == ["arn:aws:athena:ap-northeast-1:111111111111:workgroup/example-dev-analytics"] &&
      toset(local.quicksight_athena_statements["QueryWorkgroup"].Action) == toset([
        "athena:GetWorkGroup", "athena:StartQueryExecution", "athena:StopQueryExecution", "athena:GetQueryExecution",
        "athena:GetQueryResults", "athena:GetQueryResultsStream", "athena:ListQueryExecutions", "athena:BatchGetQueryExecution",
      ])
    )
    error_message = "Athena actions apply to the single workgroup ARN published by analytics"
  }

  assert {
    condition     = !strcontains(jsonencode(local.quicksight_athena_statements["QueryWorkgroup"]), "*")
    error_message = "The workgroup statement must not contain a wildcard"
  }
}

run "quicksight_athena_data_access" {
  command = plan

  assert {
    condition = (
      local.quicksight_athena_statements["ReadCuratedObjects"].Resource == ["arn:aws:s3:::example-dev-curated-111111111111/*"] &&
      local.quicksight_athena_statements["ReadCuratedObjects"].Action == ["s3:GetObject"] &&
      local.quicksight_athena_statements["ListCuratedBucket"].Resource == ["arn:aws:s3:::example-dev-curated-111111111111"]
    )
    error_message = "Curated is read-only: GetObject on objects, list on the bucket"
  }

  assert {
    condition = (
      local.quicksight_athena_statements["ReadWriteResults"].Resource == ["arn:aws:s3:::example-dev-athena-results-111111111111/*"] &&
      toset(local.quicksight_athena_statements["ReadWriteResults"].Action) == toset(["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]) &&
      local.quicksight_athena_statements["ListResultsBucket"].Resource == ["arn:aws:s3:::example-dev-athena-results-111111111111"]
    )
    error_message = "Only the athena-results bucket is writable"
  }

  assert {
    condition = alltrue([
      for s in values(local.quicksight_athena_statements) :
      !anytrue([for a in s.Action : startswith(a, "s3:Put") || startswith(a, "s3:Delete")]) || s.Resource == ["arn:aws:s3:::example-dev-athena-results-111111111111/*"]
    ])
    error_message = "No s3 write or delete outside athena-results"
  }
}

run "quicksight_athena_catalog_is_read_only_and_curated_only" {
  command = plan

  assert {
    condition = (
      toset(local.quicksight_athena_statements["ReadCuratedCatalog"].Resource) == toset([
        "arn:aws:glue:ap-northeast-1:111111111111:catalog",
        "arn:aws:glue:ap-northeast-1:111111111111:database/example_dev_curated",
        "arn:aws:glue:ap-northeast-1:111111111111:table/example_dev_curated/*",
      ]) &&
      toset(local.quicksight_athena_statements["ReadCuratedCatalog"].Action) == toset([
        "glue:GetDatabase", "glue:GetDatabases", "glue:GetTable", "glue:GetTables",
        "glue:GetPartition", "glue:GetPartitions", "glue:BatchGetPartition",
      ])
    )
    error_message = "Catalog reads are limited to the catalog root and the curated database"
  }

  assert {
    condition     = !strcontains(jsonencode(local.quicksight_athena_statements), "example_dev_raw")
    error_message = "The raw database must not appear"
  }
}

run "quicksight_athena_kms_is_the_shared_key" {
  command = plan

  assert {
    condition = (
      local.quicksight_athena_statements["UseSharedKey"].Resource == ["arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"] &&
      toset(local.quicksight_athena_statements["UseSharedKey"].Action) == toset(["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"])
    )
    error_message = "KMS use is limited to the shared key"
  }
}

run "quicksight_athena_has_exactly_these_statements" {
  command = plan

  assert {
    condition     = toset(keys(local.quicksight_athena_statements)) == toset(["QueryWorkgroup", "ReadCuratedObjects", "ListCuratedBucket", "ReadWriteResults", "ListResultsBucket", "ReadCuratedCatalog", "UseSharedKey"])
    error_message = "A new statement must come with a test"
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
      local.quicksight_athena_role.name == "example-sit-quicksight-athena" &&
      local.quicksight_athena_role.trust.source_account == "222222222222" &&
      local.firehose_statements["WriteLogs"].Resource[0] == "arn:aws:logs:ap-northeast-1:222222222222:log-group:/aws/kinesisfirehose/example-sit-*" &&
      local.firehose_statements["CreateNetworkInterface"].Resource[0] == "arn:aws:ec2:ap-northeast-1:222222222222:network-interface/*"
    )
    error_message = "Names and ARNs must follow the env and account"
  }
}

run "publishes_exactly_the_iam_app_key" {
  command = plan

  override_module {
    target = module.quicksight_athena_role
    outputs = {
      arn  = "arn:aws:iam::111111111111:role/example-dev-quicksight-athena"
      name = "example-dev-quicksight-athena"
      id   = "AROAQSATHENA"
    }
  }

  assert {
    condition     = local.published_strings == { role_quicksight_athena_arn = "arn:aws:iam::111111111111:role/example-dev-quicksight-athena" }
    error_message = "iam-app publishes only role_quicksight_athena_arn (design 7.2)"
  }
}
