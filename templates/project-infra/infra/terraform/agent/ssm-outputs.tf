# Always published, also when empty, so iam-app and application read the agent stack instead of tfvars.
locals {
  published_strings = merge(
    # One key per Runtime keeps each value under the 4096 character limit of a Standard parameter.
    {
      for r, k in local.agent_key : "agent_runtime_${k}" => jsonencode({
        arn                = module.runtime[r].runtime_arn
        id                 = module.runtime[r].runtime_id
        name               = module.runtime[r].runtime_name
        execution_role_arn = local.runtime_inputs[r].role_arn
        models             = var.agent_runtimes[r].models
        memories           = var.agent_runtimes[r].memories
        guardrails         = var.agent_runtimes[r].guardrails
        knowledge_bases    = var.agent_runtimes[r].knowledge_bases
        gateway            = var.agent_runtimes[r].gateway
        tracing            = var.agent_runtimes[r].tracing
        workload_identity  = var.agent_runtimes[r].workload_identity
      })
    },
    {
      models = jsonencode(local.models)
      guardrails = jsonencode({
        for k, g in module.guardrail : k => {
          id         = g.guardrail_id
          arn        = g.guardrail_arn
          version    = g.version
          profile_id = g.cross_region_profile_id
        }
      })
      agent_memories = jsonencode({ for k, m in module.memory : k => { id = m.memory_id, arn = m.memory_arn } })
      # Every configured knowledge base, also before its database user is ready: iam-app grants the knowledge base role
      # the secret and the bucket before the knowledge base is created. ready is false and the ids are null until then.
      knowledge_bases = jsonencode({
        for k, cfg in var.knowledge_bases : k => {
          ready                  = contains(keys(module.knowledge_base), k)
          id                     = contains(keys(module.knowledge_base), k) ? module.knowledge_base[k].knowledge_base_id : null
          arn                    = contains(keys(module.knowledge_base), k) ? module.knowledge_base[k].knowledge_base_arn : null
          embedding_model        = cfg.embedding_model
          bucket_name            = module.corpus_bucket[k].bucket_name
          bucket_arn             = module.corpus_bucket[k].arn
          inclusion_prefixes     = { for ds, d in cfg.data_sources : ds => sort(tolist(d.inclusion_prefixes)) }
          data_source_ids        = contains(keys(module.knowledge_base), k) ? module.knowledge_base[k].data_source_ids : {}
          credentials_secret_arn = aws_secretsmanager_secret.kb_db[k].arn
        }
      })
      agentcore_gateway = var.agentcore_gateway == null ? jsonencode({ enabled = false }) : jsonencode({
        enabled     = true
        arn         = module.gateway["this"].gateway_arn
        url         = module.gateway["this"].gateway_url
        lambda_arns = sort([for t in values(var.agentcore_gateway.targets) : t.lambda_arn if t.type == "lambda"])
        # iam-app grants s3:GetObject on exactly these objects.
        tool_schema_arns = sort([for t in values(var.agentcore_gateway.targets) : "arn:aws:s3:::${trimprefix(t.tool_schema_s3_uri, "s3://")}" if t.type == "lambda" && t.tool_schema_s3_uri != null])
      })
      bedrock_invoke = var.bedrock_invoke == null ? jsonencode({ enabled = false }) : jsonencode({
        enabled         = true
        role_arn        = var.bedrock_invoke.role_arn
        session_seconds = var.bedrock_invoke.session_seconds
      })
    },
  )
}

module "ssm_publish" {
  source = "../../../../../modules/ssm-publish"

  ssm_prefix = local.ssm_prefix
  stack      = "agent"
  strings    = local.published_strings
}
