# Plan-level behaviour of the search-config stack. No OpenSearch call is made: both providers are mocked, the SSM reads
# are overridden with values of the shape the earlier stacks publish, and the master secret is a fake.
# Not a mock: mock providers cannot open ephemeral resources (Terraform 1.15: "No ephemeral resource types in mock
# providers"), and no override block reaches them. This is a real aws provider with fake credentials, every API endpoint
# aimed at a closed local port and all startup calls skipped, so nothing can leave this machine. The SSM reads are
# overridden below, and read_master_secret = false keeps the ephemeral block from opening.
provider "aws" {
  region                      = "ap-northeast-1"
  access_key                  = "test-access-key"
  secret_key                  = "test-secret-key"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  endpoints {
    ssm            = "http://127.0.0.1:9"
    sts            = "http://127.0.0.1:9"
    secretsmanager = "http://127.0.0.1:9"
  }
}
mock_provider "opensearch" {}

variables {
  read_master_secret = false

  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"

  ism = {
    warm_days       = 3
    cold_days       = 7
    delete_days     = 30
    timestamp_field = "@timestamp"
  }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/opensearch_master_secret_arn"]
  values = { insecure_value = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev-opensearch-master-AbCdEf" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["search/opensearch_endpoint"]
  values = { insecure_value = "vpc-example-dev-search-abc123.ap-northeast-1.es.amazonaws.com" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_firehose_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-firehose" }
}

run "reads_only_keys_published_earlier" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      opensearch_master_secret_arn = "foundation/opensearch_master_secret_arn"
      opensearch_endpoint          = "search/opensearch_endpoint"
      role_firehose_arn            = "iam-base/role_firehose_arn"
    } && local.ssm_input_lists == {}
    error_message = "search-config must read the master secret ARN from foundation, the endpoint from search and the Firehose role from iam-base, and nothing else"
  }
}

# The pipeline stack's Firehose OpenSearch destination writes the index example-dev-events (design section 7.4).
run "patterns_cover_the_pipeline_index_and_nothing_wider" {
  command = plan

  assert {
    condition     = jsonencode(local.index_patterns) == jsonencode(["example-dev-events*"]) && startswith("example-dev-events", trimsuffix(local.index_patterns[0], "*"))
    error_message = "index_patterns must be <name_prefix>-events* so the writer role, the ISM policy and the template cover the index the pipeline writes"
  }
}

run "provider_url_is_https_on_the_published_endpoint" {
  command = plan

  assert {
    condition     = local.opensearch_url == format("%s://%s", "https", "vpc-example-dev-search-abc123.ap-northeast-1.es.amazonaws.com")
    error_message = "The opensearch provider must talk HTTPS to the endpoint search published"
  }
}

run "ism_policy_uses_cumulative_age_and_a_timestamp_field" {
  command = plan

  assert {
    condition = (
      local.ism_policies["logs"].warm_days == 3 &&
      local.ism_policies["logs"].cold_days == 7 &&
      local.ism_policies["logs"].delete_days == 30
    )
    error_message = "The dev ISM policy must move to warm on day 3, to cold on day 7 and delete on day 30 (design section 7.5)"
  }

  assert {
    condition     = local.ism_policies["logs"].timestamp_field == "@timestamp" && jsonencode(local.ism_policies["logs"].index_patterns) == jsonencode(["example-dev-events*"])
    error_message = "The policy must name the timestamp field cold migration needs and apply to the index patterns"
  }
}

run "firehose_writer_is_limited_to_the_firehose_role_and_prefix" {
  command = plan

  assert {
    condition     = toset(keys(local.writer_roles)) == toset(["firehose_writer"])
    error_message = "search-config must define exactly one writer role, firehose_writer"
  }

  assert {
    condition = (
      jsonencode(local.writer_roles["firehose_writer"].backend_role_arns) == jsonencode(["arn:aws:iam::111111111111:role/example-dev-firehose"]) &&
      jsonencode(local.writer_roles["firehose_writer"].index_patterns) == jsonencode(["example-dev-events*"])
    )
    error_message = "firehose_writer must map only the iam-base Firehose role and only the index prefix"
  }
}

run "no_ops_roles_means_no_manager_mappings" {
  command = plan

  assert {
    condition     = length(local.role_mappings) == 0
    error_message = "Empty ops role lists must create no ultrawarm_manager or cold_manager mapping"
  }
}

run "ops_roles_map_only_the_two_manager_roles" {
  command = plan

  variables {
    ultrawarm_manager_role_arns = ["arn:aws:iam::111111111111:role/example-dev-ops"]
    cold_manager_role_arns      = ["arn:aws:iam::111111111111:role/example-dev-ops"]
  }

  assert {
    condition     = toset(keys(local.role_mappings)) == toset(["ultrawarm_manager", "cold_manager"])
    error_message = "Only ultrawarm_manager and cold_manager may be mapped; never all_access or security_manager"
  }

  assert {
    condition     = jsonencode(local.role_mappings["cold_manager"].backend_role_arns) == jsonencode(["arn:aws:iam::111111111111:role/example-dev-ops"])
    error_message = "cold_manager must map the given ops role"
  }
}

run "index_template_defines_the_timestamp_as_date" {
  command = plan

  assert {
    condition     = jsondecode(local.index_templates["firehose"].mappings).properties["@timestamp"].type == "date"
    error_message = "The index template must define the ISM timestamp field as a date"
  }
}

run "publishes_exactly_the_search_config_contract" {
  command = plan

  assert {
    condition     = toset(keys(local.published_strings)) == toset(["firehose_writer_role"]) && toset(keys(local.published_lists)) == toset(["ism_policy_ids"])
    error_message = "search-config must publish firehose_writer_role (String) and ism_policy_ids (StringList) and nothing else"
  }

  assert {
    condition     = local.published_strings["firehose_writer_role"] == "firehose_writer"
    error_message = "firehose_writer_role must be the FGAC role name"
  }

  assert {
    condition = module.ssm_publish.names == {
      firehose_writer_role = "/example/dev/search-config/firehose_writer_role"
      ism_policy_ids       = "/example/dev/search-config/ism_policy_ids"
    }
    error_message = "ssm-publish must write the two contract keys under the search-config stack path"
  }
}
