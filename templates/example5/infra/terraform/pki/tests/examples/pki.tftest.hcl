# Run by scripts/validate.sh with -var-file=envs/examples/pki.tfvars; it checks the example that turns the CA on.
mock_provider "aws" {}

run "example_enables_a_root_ca" {
  command = plan

  override_module {
    target = module.ca
    outputs = {
      ca_arn             = "arn:aws:acm-pca:ap-northeast-1:111111111111:certificate-authority/11111111-2222-3333-4444-555555555555"
      ca_certificate_pem = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----"
      csr                = "-----BEGIN CERTIFICATE REQUEST-----\nMIIB\n-----END CERTIFICATE REQUEST-----"
    }
  }

  assert {
    condition     = length(module.ca) == 1 && local.ca.type == "ROOT" && local.ca.subordinate_certificate == null
    error_message = "The example must create one ROOT CA"
  }

  assert {
    condition     = jsondecode(local.published_strings["ca"]).enabled == true
    error_message = "With the example, the ca key must say enabled = true"
  }
}

run "example_ca_settings" {
  command = plan

  assert {
    condition     = local.ca.subject.common_name == "example-dev-device-ca" && local.ca.key_algorithm == "EC_prime256v1" && local.ca.usage_mode == "GENERAL_PURPOSE"
    error_message = "The example CA is a general-purpose P-256 CA named <name_prefix>-device-ca"
  }
}

run "example_env_and_account_correspond" {
  command = plan

  assert {
    condition     = var.env == "dev" && var.expected_account_id == "111111111111"
    error_message = "The example uses the dev placeholders"
  }
}
