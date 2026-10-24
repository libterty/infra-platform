locals {
  # The Firehose OpenSearch destination of the pipeline stack writes the index <name_prefix>-events (design section 7.4);
  # the policy, the writer role and the template all cover it, and nothing else.
  index_patterns = ["${local.name_prefix}-events*"]

  ism_policies = {
    logs = {
      index_patterns  = local.index_patterns
      warm_days       = var.ism.warm_days
      cold_days       = var.ism.cold_days
      delete_days     = var.ism.delete_days
      timestamp_field = var.ism.timestamp_field
    }
  }

  # Only the Firehose role of iam-base is mapped, and only to the index prefix it writes.
  writer_roles = {
    firehose_writer = {
      index_patterns    = local.index_patterns
      backend_role_arns = [module.in.strings["role_firehose_arn"]]
    }
  }

  # Only the two built-in manager roles ISM needs; all_access and security_manager stay with the master user (design K18).
  role_mappings = merge(
    length(var.ultrawarm_manager_role_arns) == 0 ? {} : { ultrawarm_manager = { backend_role_arns = var.ultrawarm_manager_role_arns } },
    length(var.cold_manager_role_arns) == 0 ? {} : { cold_manager = { backend_role_arns = var.cold_manager_role_arns } },
  )

  # ISM moves an index to cold by its timestamp field, so the template defines it as a date.
  index_templates = {
    firehose = {
      index_patterns   = local.index_patterns
      number_of_shards = 1
      mappings         = jsonencode({ properties = { (var.ism.timestamp_field) = { type = "date" } } })
    }
  }
}

module "config" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/opensearch-config/aws"
  version = "~> 0.1.0"

  ism_policies    = local.ism_policies
  writer_roles    = local.writer_roles
  role_mappings   = local.role_mappings
  index_templates = local.index_templates
}
