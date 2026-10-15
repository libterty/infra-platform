# One corpus bucket per knowledge base, so the knowledge base role reads exactly its own bucket. SSE-S3: which key
# policy Bedrock needs for an SSE-KMS bucket has not been tested. Objects never expire; the next sync would otherwise
# drop the vectors of expired documents.
locals {
  corpus_buckets = {
    for k in keys(var.knowledge_bases) : k => {
      name          = "${local.name_prefix}-kb-${k}-${var.expected_account_id}"
      kms_key_arn   = null
      never_expire  = true
      log_delivery  = []
      force_destroy = false
    }
  }
}

module "corpus_bucket" {
  source   = "../../../../../modules/s3-bucket"
  for_each = local.corpus_buckets

  name          = each.value.name
  kms_key_arn   = each.value.kms_key_arn
  never_expire  = each.value.never_expire
  log_delivery  = each.value.log_delivery
  force_destroy = each.value.force_destroy
}

# One database user secret per knowledge base, created without a value like the foundation secret: the project writes
# the user name and password outside Terraform, so they never reach tfvars, SSM or state.
resource "aws_secretsmanager_secret" "kb_db" {
  for_each = var.knowledge_bases

  name        = "${local.name_prefix}-kb-${each.key}-db"
  description = "Database user of knowledge base ${local.name_prefix}-${each.key}. The value is written outside Terraform."
  kms_key_id  = module.in.strings["kms_key_arn"]
}

locals {
  # guards.tf fails the plan when the database cannot hold a knowledge base; the modules are left out in that case so
  # the precondition is the error that is reported. A knowledge base waits for database_user_ready, because Bedrock
  # may check the database user when it creates the knowledge base (not verified).
  knowledge_base_database_ready = (
    try(local.database.enabled, false) &&
    try(local.database.deployment, "rds") != "rds" &&
    try(local.database.data_api, false) &&
    try(local.database.cluster_arn, null) != null
  )

  knowledge_base_inputs = {
    for k, kb in var.knowledge_bases : k => {
      name                 = "${local.name_prefix}-${k}"
      embedding_model_arn  = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.models[kb.embedding_model].foundation_model_id}"
      embedding_dimensions = kb.embedding_dimensions
      aurora = {
        cluster_arn            = local.database.cluster_arn
        credentials_secret_arn = aws_secretsmanager_secret.kb_db[k].arn
        database_name          = local.database.name
        table_name             = kb.table_name
        field_mapping          = kb.field_mapping
      }
      data_sources = {
        for ds, cfg in kb.data_sources : ds => {
          bucket_arn              = module.corpus_bucket[k].arn
          bucket_owner_account_id = var.expected_account_id
          inclusion_prefixes      = cfg.inclusion_prefixes
        }
      }
    } if local.knowledge_base_database_ready && kb.database_user_ready
  }
}

module "knowledge_base" {
  source   = "../../../../../modules/bedrock-knowledge-base"
  for_each = local.knowledge_base_inputs

  name                 = each.value.name
  role_arn             = module.in_agents.strings["role_bedrock_kb_arn"]
  embedding_model_arn  = each.value.embedding_model_arn
  embedding_dimensions = each.value.embedding_dimensions
  aurora               = each.value.aurora
  data_sources         = each.value.data_sources
}
