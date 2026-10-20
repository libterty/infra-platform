locals {
  published_strings = {
    alarm_topic_arn = module.alarm_topic.topic_arn
    # The application verifies tokens with the public key and signs them with the private one.
    signing_secret_arn = aws_secretsmanager_secret.this["signing_public_key"].arn
    app_secret_arn     = aws_secretsmanager_secret.this["signing_private_key"].arn
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "foundation"
  strings    = local.published_strings
}
