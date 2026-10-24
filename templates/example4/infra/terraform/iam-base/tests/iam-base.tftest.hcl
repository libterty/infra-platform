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
  target = module.in.data.aws_ssm_parameter.this["network/sg_quicksight_id"]
  values = { insecure_value = "sg-0aaaaaaa00000008" }
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
  target = module.in.data.aws_ssm_parameter.this["storage/glue_assets_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-dev-glue-assets-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/raw_database_name"]
  values = { insecure_value = "example_dev_raw" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/curated_database_name"]
  values = { insecure_value = "example_dev_curated" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_app"]
  values = { insecure_value = "subnet-0app1,subnet-0app2" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dat1,subnet-0dat2" }
}

run "reads_only_foundation_network_and_storage_keys" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn            = "foundation/kms_key_arn"
      sg_quicksight_id       = "network/sg_quicksight_id"
      raw_bucket_arn         = "storage/raw_bucket_arn"
      curated_bucket_arn     = "storage/curated_bucket_arn"
      glue_assets_bucket_arn = "storage/glue_assets_bucket_arn"
      raw_database_name      = "storage/raw_database_name"
      curated_database_name  = "storage/curated_database_name"
      } && local.ssm_input_lists == {
      subnet_ids_app  = "network/subnet_ids_app"
      subnet_ids_data = "network/subnet_ids_data"
    }
    error_message = "iam-base must read exactly the keys of earlier stacks that its policies need (design section 8)"
  }
}

run "six_roles_named_after_the_prefix" {
  command = plan

  assert {
    condition     = toset(keys(local.roles)) == toset(["firehose", "glue_crawler", "glue_job", "glue_events", "redshift", "quicksight_vpc"])
    error_message = "iam-base must create exactly the six roles of design section 8"
  }

  assert {
    condition = (
      local.roles["firehose"].name == "example-dev-firehose" &&
      local.roles["glue_crawler"].name == "example-dev-glue-crawler" &&
      local.roles["glue_job"].name == "example-dev-glue-job" &&
      local.roles["glue_events"].name == "example-dev-glue-events" &&
      local.roles["redshift"].name == "example-dev-redshift" &&
      local.roles["quicksight_vpc"].name == "example-dev-quicksight-vpc"
    )
    error_message = "Role names must be <name_prefix>-<role with hyphens>"
  }
}

run "role_module_receives_name_trust_and_policies" {
  command = plan

  assert {
    condition = alltrue([
      for f in ["name", "trust", "inline_policies"] :
      length(regexall("(?m)^\\s*${f}\\s*=\\s*each\\.value\\.${f == "inline_policies" ? "policies" : f}\\s*$", file("${path.module}/roles.tf"))) == 1
    ])
    error_message = "The role module call must take name, trust and inline_policies from the role spec"
  }
}

run "every_role_trusts_one_service_in_this_account" {
  command = plan

  assert {
    condition = alltrue([
      for k, r in local.roles : r.trust.source_account == "111111111111" && length(r.trust.service_principals) > 0
    ])
    error_message = "Every trust policy must carry source_account (the confused deputy guard)"
  }

  assert {
    condition = (
      toset(local.roles["firehose"].trust.service_principals) == toset(["firehose.amazonaws.com"]) &&
      toset(local.roles["glue_crawler"].trust.service_principals) == toset(["glue.amazonaws.com"]) &&
      toset(local.roles["glue_job"].trust.service_principals) == toset(["glue.amazonaws.com"]) &&
      toset(local.roles["glue_events"].trust.service_principals) == toset(["events.amazonaws.com"]) &&
      toset(local.roles["redshift"].trust.service_principals) == toset(["redshift.amazonaws.com", "redshift-serverless.amazonaws.com"]) &&
      toset(local.roles["quicksight_vpc"].trust.service_principals) == toset(["quicksight.amazonaws.com"])
    )
    error_message = "Each role must trust the service that uses it (Redshift: provisioned and Serverless)"
  }
}

# The Firehose policy needs the domain ARN, which only exists after the search stack; iam-app attaches it.
run "firehose_has_trust_only_and_no_inline_policy" {
  command = plan

  assert {
    condition     = length(local.roles["firehose"].policies) == 0
    error_message = "The firehose role must have no inline policy in iam-base; iam-app attaches it (design section 8)"
  }

  assert {
    condition     = local.roles["firehose"].trust.source_arn == null
    error_message = "The firehose trust has no source_arn: the delivery streams do not exist yet"
  }
}

# Design K21: the workflow exists only after the pipeline stack, so the ARN comes from the naming rule that
# glue-etl uses (workflow <name_prefix>-raw-to-curated, rule and trigger <workflow>-s3-event). Exact strings, no wildcard.
run "glue_events_policy_is_the_single_workflow_arn" {
  command = plan

  assert {
    condition     = local.workflow_arn == "arn:aws:glue:ap-northeast-1:111111111111:workflow/example-dev-raw-to-curated"
    error_message = "The workflow ARN must come from the naming rule <name_prefix>-raw-to-curated"
  }

  assert {
    condition = (
      length(local.roles["glue_events"].policies) == 1 &&
      jsondecode(one(values(local.roles["glue_events"].policies))).Statement == [{
        Sid      = "NotifyWorkflowEvent"
        Effect   = "Allow"
        Action   = ["glue:notifyEvent"]
        Resource = ["arn:aws:glue:ap-northeast-1:111111111111:workflow/example-dev-raw-to-curated"]
      }]
    )
    error_message = "glue_events may only call glue:notifyEvent on the single workflow ARN"
  }

  assert {
    condition     = !strcontains(one(values(local.roles["glue_events"].policies)), "*")
    error_message = "The glue_events policy must not contain a wildcard"
  }
}

run "glue_events_trust_source_arn_is_the_single_rule_arn" {
  command = plan

  assert {
    condition     = local.roles["glue_events"].trust.source_arn == "arn:aws:events:ap-northeast-1:111111111111:rule/example-dev-raw-to-curated-s3-event"
    error_message = "The trust source_arn must be the single EventBridge rule ARN of the naming rule <workflow>-s3-event"
  }

  assert {
    condition     = !strcontains(local.roles["glue_events"].trust.source_arn, "*") && !strcontains(local.roles["glue_events"].trust.source_arn, "?")
    error_message = "The trust source_arn must not contain a wildcard"
  }
}

# The naming rule has two homes (here and glue-etl in the pipeline stack); the expected strings are written out so
# a change to either side has to change a test.
run "naming_rule_for_sit" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.workflow_arn == "arn:aws:glue:ap-northeast-1:222222222222:workflow/example-sit-raw-to-curated" && local.roles["glue_events"].trust.source_arn == "arn:aws:events:ap-northeast-1:222222222222:rule/example-sit-raw-to-curated-s3-event"
    error_message = "The workflow and rule ARNs must follow the env and account"
  }
}

# Resource "*" is only allowed for actions that cannot be scoped; each one is listed here with the reason.
#   ec2:DescribeSubnets, ec2:DescribeSecurityGroups: Describe actions do not support resource-level permissions.
run "no_policy_uses_a_bare_wildcard_resource_except_the_allow_list" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for k, r in local.roles : [
        for p in values(r.policies) : [
          for s in jsondecode(p).Statement :
          !contains(s.Resource, "*") || alltrue([for a in s.Action : contains(["ec2:DescribeSubnets", "ec2:DescribeSecurityGroups"], a)])
        ]
      ]
    ]))
    error_message = "Only ec2:DescribeSubnets and ec2:DescribeSecurityGroups may use Resource *"
  }

  assert {
    condition = alltrue(flatten([
      for k, r in local.roles : [
        for p in values(r.policies) : [
          for s in jsondecode(p).Statement : [
            for res in s.Resource : res == "*" || (!startswith(res, "*") && res != "arn:aws:s3:::*" && !can(regex("^arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]*:\\*$", res)))
          ]
        ]
      ]
    ]))
    error_message = "Apart from the allow-listed bare wildcard, no Resource may start with a wildcard or be an account-wide wildcard such as arn:aws:s3:::* or arn:aws:glue:<region>:<account>:*"
  }

  assert {
    condition = alltrue(flatten([
      for k, r in local.roles : [
        for p in values(r.policies) : [
          for s in jsondecode(p).Statement : s.Effect == "Allow" && !contains(s.Action, "*") && alltrue([for a in s.Action : !endswith(a, ":*")])
        ]
      ]
    ]))
    error_message = "Statements must be Allow and may not use * or service:* actions"
  }
}

run "only_quicksight_vpc_uses_the_wildcard_resource" {
  command = plan

  assert {
    condition = [
      for k, r in local.roles : k if anytrue(flatten([for p in values(r.policies) : [for s in jsondecode(p).Statement : contains(s.Resource, "*")]]))
    ] == ["quicksight_vpc"]
    error_message = "quicksight_vpc is the only role with a Resource * statement, and only for the two Describe actions"
  }
}

run "glue_crawler_reads_the_lake_and_manages_both_databases" {
  command = plan

  assert {
    condition = (
      toset(flatten([for s in jsondecode(local.roles["glue_crawler"].policies["crawl-and-catalog"]).Statement : s.Resource if contains(s.Action, "s3:GetObject")])) == toset([
        "arn:aws:s3:::example-dev-raw-111111111111/raw/*",
        "arn:aws:s3:::example-dev-curated-111111111111/*",
      ])
    )
    error_message = "The crawler may read objects only under raw/ of the raw bucket and in the curated bucket"
  }

  assert {
    condition = (
      toset(flatten([for s in jsondecode(local.roles["glue_crawler"].policies["crawl-and-catalog"]).Statement : s.Resource if contains(s.Action, "glue:CreateTable")])) == toset([
        "arn:aws:glue:ap-northeast-1:111111111111:catalog",
        "arn:aws:glue:ap-northeast-1:111111111111:database/example_dev_raw",
        "arn:aws:glue:ap-northeast-1:111111111111:table/example_dev_raw/*",
        "arn:aws:glue:ap-northeast-1:111111111111:database/example_dev_curated",
        "arn:aws:glue:ap-northeast-1:111111111111:table/example_dev_curated/*",
      ])
    )
    error_message = "The crawler may change the catalog only in the catalog root and the two databases"
  }

  assert {
    condition     = !anytrue(flatten([for s in jsondecode(local.roles["glue_crawler"].policies["crawl-and-catalog"]).Statement : [for a in s.Action : startswith(a, "s3:Put") || startswith(a, "s3:Delete")]]))
    error_message = "The crawler must not write or delete objects"
  }
}

run "glue_job_reads_raw_writes_curated_and_uses_assets" {
  command = plan

  assert {
    condition = (
      toset(flatten([for s in jsondecode(local.roles["glue_job"].policies["etl-data-catalog-and-logs"]).Statement : s.Resource if contains(s.Action, "s3:PutObject")])) == toset([
        "arn:aws:s3:::example-dev-curated-111111111111/*",
        "arn:aws:s3:::example-dev-glue-assets-111111111111/tmp/*",
      ])
    )
    error_message = "The job may write only to the curated bucket and to glue-assets/tmp/"
  }

  assert {
    condition = (
      toset(flatten([for s in jsondecode(local.roles["glue_job"].policies["etl-data-catalog-and-logs"]).Statement : s.Resource if contains(s.Action, "s3:GetObject")])) == toset([
        "arn:aws:s3:::example-dev-raw-111111111111/raw/*",
        "arn:aws:s3:::example-dev-curated-111111111111/*",
        "arn:aws:s3:::example-dev-glue-assets-111111111111/scripts/*",
        "arn:aws:s3:::example-dev-glue-assets-111111111111/tmp/*",
      ])
    )
    error_message = "The job may read raw/, curated, glue-assets/scripts/ and glue-assets/tmp/ only"
  }

  assert {
    condition = (
      toset(flatten([for s in jsondecode(local.roles["glue_job"].policies["etl-data-catalog-and-logs"]).Statement : s.Resource if contains(s.Action, "glue:CreateTable")])) == toset([
        "arn:aws:glue:ap-northeast-1:111111111111:catalog",
        "arn:aws:glue:ap-northeast-1:111111111111:database/example_dev_curated",
        "arn:aws:glue:ap-northeast-1:111111111111:table/example_dev_curated/*",
      ])
    )
    error_message = "The job may change the catalog only in the curated database; raw is read-only"
  }

  assert {
    condition = (
      toset(flatten([for s in jsondecode(local.roles["glue_job"].policies["etl-data-catalog-and-logs"]).Statement : s.Resource if contains(s.Action, "glue:GetJobBookmark")])) == toset([
        "arn:aws:glue:ap-northeast-1:111111111111:job/example-dev-*",
      ])
    )
    error_message = "Job bookmark access is limited to jobs named <name_prefix>-*"
  }
}

run "glue_roles_use_the_shared_key_for_kms" {
  command = plan

  assert {
    condition = alltrue([
      for role, name in { glue_crawler = "crawl-and-catalog", glue_job = "etl-data-catalog-and-logs" } :
      toset(flatten([for s in jsondecode(local.roles[role].policies[name]).Statement : s.Resource if contains(s.Action, "kms:Decrypt")])) == toset(["arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"])
    ])
    error_message = "Glue roles may use only the shared key published by foundation (it also encrypts the catalog)"
  }
}

run "glue_roles_write_logs_only_under_aws_glue" {
  command = plan

  assert {
    condition = alltrue([
      for role, name in { glue_crawler = "crawl-and-catalog", glue_job = "etl-data-catalog-and-logs" } :
      toset(flatten([for s in jsondecode(local.roles[role].policies[name]).Statement : s.Resource if contains(s.Action, "logs:PutLogEvents")])) == toset([
        "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws-glue/*",
        "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws-glue/*:log-stream:*",
      ])
    ])
    error_message = "Glue roles may write log events only to log groups under /aws-glue/"
  }
}

run "redshift_only_reads_curated_and_its_catalog" {
  command = plan

  assert {
    condition = (
      toset(flatten([for s in jsondecode(local.roles["redshift"].policies["read-curated"]).Statement : s.Resource if contains(s.Action, "s3:GetObject")])) == toset(["arn:aws:s3:::example-dev-curated-111111111111/*"]) &&
      toset(flatten([for s in jsondecode(local.roles["redshift"].policies["read-curated"]).Statement : s.Resource if contains(s.Action, "s3:ListBucket")])) == toset(["arn:aws:s3:::example-dev-curated-111111111111"])
    )
    error_message = "Redshift may read objects of the curated bucket only"
  }

  assert {
    condition = (
      toset(flatten([for s in jsondecode(local.roles["redshift"].policies["read-curated"]).Statement : s.Resource if contains(s.Action, "glue:GetTable")])) == toset([
        "arn:aws:glue:ap-northeast-1:111111111111:catalog",
        "arn:aws:glue:ap-northeast-1:111111111111:database/example_dev_curated",
        "arn:aws:glue:ap-northeast-1:111111111111:table/example_dev_curated/*",
      ]) &&
      toset(flatten([for s in jsondecode(local.roles["redshift"].policies["read-curated"]).Statement : s.Resource if contains(s.Action, "kms:Decrypt")])) == toset(["arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"])
    )
    error_message = "Redshift may read only the curated database and decrypt with the shared key"
  }

  assert {
    condition     = !anytrue(flatten([for s in jsondecode(local.roles["redshift"].policies["read-curated"]).Statement : [for a in s.Action : !contains(["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation", "kms:Decrypt"], a) && !startswith(a, "glue:Get") && !startswith(a, "glue:BatchGet")]]))
    error_message = "Redshift must be read-only: S3 reads, catalog reads and kms:Decrypt"
  }
}

run "quicksight_vpc_network_interface_actions" {
  command = plan

  assert {
    condition = (
      toset(flatten([for s in jsondecode(local.roles["quicksight_vpc"].policies["connection-network"]).Statement : s.Action if !contains(s.Resource, "*")])) == toset(["ec2:CreateNetworkInterface", "ec2:ModifyNetworkInterfaceAttribute", "ec2:DeleteNetworkInterface"]) &&
      toset(flatten([for s in jsondecode(local.roles["quicksight_vpc"].policies["connection-network"]).Statement : s.Action if contains(s.Resource, "*")])) == toset(["ec2:DescribeSubnets", "ec2:DescribeSecurityGroups"])
    )
    error_message = "The VPC connection role needs the three network interface actions (scoped) and the two Describe actions (Resource *)"
  }

  assert {
    condition = toset(flatten([for s in jsondecode(local.roles["quicksight_vpc"].policies["connection-network"]).Statement : s.Resource if contains(s.Action, "ec2:CreateNetworkInterface")])) == toset([
      "arn:aws:ec2:ap-northeast-1:111111111111:network-interface/*",
      "arn:aws:ec2:ap-northeast-1:111111111111:subnet/subnet-0app1",
      "arn:aws:ec2:ap-northeast-1:111111111111:subnet/subnet-0app2",
      "arn:aws:ec2:ap-northeast-1:111111111111:subnet/subnet-0dat1",
      "arn:aws:ec2:ap-northeast-1:111111111111:subnet/subnet-0dat2",
      "arn:aws:ec2:ap-northeast-1:111111111111:security-group/sg-0aaaaaaa00000008",
    ])
    error_message = "Network interfaces may be created only in the VPC subnets and with the QuickSight security group"
  }
}

run "policies_never_name_a_foreign_bucket" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for k, r in local.roles : [
        for p in values(r.policies) : [
          for s in jsondecode(p).Statement : [
            for res in s.Resource : !startswith(res, "arn:aws:s3:::") || anytrue([
              for b in ["example-dev-raw-111111111111", "example-dev-curated-111111111111", "example-dev-glue-assets-111111111111"] : res == "arn:aws:s3:::${b}" || startswith(res, "arn:aws:s3:::${b}/")
            ])
          ]
        ]
      ]
    ]))
    error_message = "S3 resources must be one of the three data lake buckets published by storage (athena-results is for iam-app)"
  }
}

run "publishes_exactly_the_iam_base_keys" {
  command = plan

  override_module {
    target = module.role["firehose"]
    outputs = {
      arn  = "arn:aws:iam::111111111111:role/example-dev-firehose"
      name = "example-dev-firehose"
      id   = "AROAFIREHOSE"
    }
  }

  override_module {
    target = module.role["glue_crawler"]
    outputs = {
      arn  = "arn:aws:iam::111111111111:role/example-dev-glue-crawler"
      name = "example-dev-glue-crawler"
      id   = "AROAGLUECRAWLER"
    }
  }

  override_module {
    target = module.role["glue_job"]
    outputs = {
      arn  = "arn:aws:iam::111111111111:role/example-dev-glue-job"
      name = "example-dev-glue-job"
      id   = "AROAGLUEJOB"
    }
  }

  override_module {
    target = module.role["glue_events"]
    outputs = {
      arn  = "arn:aws:iam::111111111111:role/example-dev-glue-events"
      name = "example-dev-glue-events"
      id   = "AROAGLUEEVENTS"
    }
  }

  override_module {
    target = module.role["redshift"]
    outputs = {
      arn  = "arn:aws:iam::111111111111:role/example-dev-redshift"
      name = "example-dev-redshift"
      id   = "AROAREDSHIFT"
    }
  }

  override_module {
    target = module.role["quicksight_vpc"]
    outputs = {
      arn  = "arn:aws:iam::111111111111:role/example-dev-quicksight-vpc"
      name = "example-dev-quicksight-vpc"
      id   = "AROAQUICKSIGHT"
    }
  }

  assert {
    condition = local.published_strings == {
      role_firehose_arn       = "arn:aws:iam::111111111111:role/example-dev-firehose"
      role_firehose_name      = "example-dev-firehose"
      role_glue_crawler_arn   = "arn:aws:iam::111111111111:role/example-dev-glue-crawler"
      role_glue_job_arn       = "arn:aws:iam::111111111111:role/example-dev-glue-job"
      role_glue_events_arn    = "arn:aws:iam::111111111111:role/example-dev-glue-events"
      role_redshift_arn       = "arn:aws:iam::111111111111:role/example-dev-redshift"
      role_quicksight_vpc_arn = "arn:aws:iam::111111111111:role/example-dev-quicksight-vpc"
    }
    error_message = "iam-base must publish exactly the seven String keys of design section 7.2, from the matching roles"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      role_firehose_arn       = "/example/dev/iam-base/role_firehose_arn"
      role_firehose_name      = "/example/dev/iam-base/role_firehose_name"
      role_glue_crawler_arn   = "/example/dev/iam-base/role_glue_crawler_arn"
      role_glue_job_arn       = "/example/dev/iam-base/role_glue_job_arn"
      role_glue_events_arn    = "/example/dev/iam-base/role_glue_events_arn"
      role_redshift_arn       = "/example/dev/iam-base/role_redshift_arn"
      role_quicksight_vpc_arn = "/example/dev/iam-base/role_quicksight_vpc_arn"
    }
    error_message = "ssm-publish must write the contract keys under the iam-base stack path"
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
