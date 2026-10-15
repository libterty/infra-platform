# High traffic: everything of standard, plus a tracked model for cost allocation, a knowledge base on the Aurora
# database and a gateway. Copy to envs/<env>.tfvars and adjust; this file is not applied by itself.
# The knowledge base needs db.data_api = true in data, knowledge_base and gateway in iam-base agent_service_roles, and a
# dedicated database user whose secret the project creates (never the master secret).
project             = "alpha"
env                 = "prod"
expected_account_id = "222222222222"

agent_runtimes = {
  assistant = {
    image_tag       = "0000000" # replace with the tag your CI pushed
    models          = ["chat"]
    memories        = ["conversation"]
    guardrails      = ["safety"]
    knowledge_bases = ["products"]
    gateway         = true
    tracing         = true
    session_lifecycle = {
      idle_session_timeout = 900
      max_lifetime         = 28800
    }
  }
}

models = {
  chat      = { foundation_model_id = "anthropic.claude-sonnet-4-5-20250929-v1:0", inference_profile_prefix = "global", tracked = true }
  embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" }
}

guardrails = {
  safety = {
    blocked_input_message   = "This request cannot be processed."
    blocked_output_message  = "This answer cannot be shown."
    cross_region_profile_id = "apac.guardrail.v1:0"
    content_filters = {
      PROMPT_ATTACK = { input_strength = "HIGH", output_strength = "NONE" }
      HATE          = { input_strength = "HIGH", output_strength = "HIGH" }
    }
  }
}

memories = {
  conversation = {
    event_expiry_days = 30
    strategies = {
      facts = { type = "SEMANTIC", namespaces = ["/actors/{actorId}/facts"] }
    }
  }
}

knowledge_bases = {
  products = {
    embedding_model        = "embedding"
    embedding_dimensions   = 1024
    credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:222222222222:secret:alpha-prod/kb-products-AbCdEf"
    data_sources = {
      manuals = { inclusion_prefixes = ["manuals/"] }
    }
  }
}

agentcore_gateway = {
  targets = {
    order-lookup = {
      type               = "lambda"
      lambda_arn         = "arn:aws:lambda:ap-northeast-1:222222222222:function:alpha-prod-order-lookup"
      tool_schema_s3_uri = "s3://alpha-prod-tool-schemas/order-lookup.json"
    }
  }
}
