mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  alarm_emails        = ["ops@example.com"]
}

override_module {
  target = module.alarm_topic
  outputs = {
    topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
  }
}

run "alarm_topic_has_only_email_subscriptions" {
  command = plan

  assert {
    condition     = module.alarm_topic.topic_arn == "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
    error_message = "The alarm topic output must reach the published values"
  }

  assert {
    condition     = local.alarm_topic.name == "example-dev-alarms" && local.alarm_topic.email_subscriptions == tolist(["ops@example.com"]) && length(local.alarm_topic) == 2
    error_message = "The topic must be named <project>-<env>-alarms and carry only the email subscriptions from alarm_emails"
  }
}

run "alarm_emails_must_not_be_empty" {
  command = plan

  variables {
    alarm_emails = []
  }

  expect_failures = [var.alarm_emails]
}

run "alarm_emails_must_look_like_addresses" {
  command = plan

  variables {
    alarm_emails = ["not-an-address"]
  }

  expect_failures = [var.alarm_emails]
}

run "two_secret_containers_with_a_seven_day_recovery_window" {
  command = plan

  assert {
    condition     = toset(keys(module.secrets)) == toset(["signing_public_key", "signing_private_key"])
    error_message = "foundation must declare exactly the public and the private signing key containers"
  }

  assert {
    condition     = local.secret_recovery_window_in_days == 7
    error_message = "A deleted secret must stay recoverable for 7 days; 0 would delete it at once"
  }

  assert {
    condition = {
      for k, s in module.secrets : k => s.name
      } == {
      signing_public_key  = "example-dev/app-signing-public-key"
      signing_private_key = "example-dev/app-signing-private-key"
    }
    error_message = "Secret names must be <project>-<env>/<name>"
  }

  assert {
    condition     = local.secret_kms_key_arn == null
    error_message = "Without a project key the secrets use the AWS managed Secrets Manager key"
  }
}

run "publishes_the_topic_and_the_two_secrets" {
  command = plan

  override_resource {
    target          = module.secrets["signing_public_key"].aws_secretsmanager_secret.this
    override_during = plan
    values = {
      arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-public-key-AbCdEf"
    }
  }

  override_resource {
    target          = module.secrets["signing_private_key"].aws_secretsmanager_secret.this
    override_during = plan
    values = {
      arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-private-key-GhIjKl"
    }
  }

  assert {
    condition = local.published_strings == {
      alarm_topic_arn                = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
      signing_private_key_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-private-key-GhIjKl"
      signing_public_key_secret_arn  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-public-key-AbCdEf"
    }
    error_message = "alarm_topic_arn comes from the topic, signing_public_key_secret_arn from the public key container, signing_private_key_secret_arn from the private key container"
  }

  assert {
    condition = module.ssm_publish.names == {
      alarm_topic_arn                = "/example/dev/foundation/alarm_topic_arn"
      signing_private_key_secret_arn = "/example/dev/foundation/signing_private_key_secret_arn"
      signing_public_key_secret_arn  = "/example/dev/foundation/signing_public_key_secret_arn"
    }
    error_message = "ssm-publish must write exactly the three foundation keys under the foundation path"
  }
}
