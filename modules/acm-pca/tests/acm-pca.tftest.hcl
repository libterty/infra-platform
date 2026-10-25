mock_provider "aws" {}

override_resource {
  target          = aws_acmpca_certificate_authority.this
  override_during = plan
  values = {
    arn                         = "arn:aws:acm-pca:ap-northeast-1:111111111111:certificate-authority/1234abcd-12ab-34cd-56ef-1234567890ab"
    certificate_signing_request = "-----BEGIN CERTIFICATE REQUEST-----\nMIIBmock\n-----END CERTIFICATE REQUEST-----"
  }
}

override_resource {
  target          = aws_acmpca_certificate.root
  override_during = plan
  values = {
    certificate       = "-----BEGIN CERTIFICATE-----\nMIIBroot\n-----END CERTIFICATE-----"
    certificate_chain = ""
  }
}

variables {
  type = "ROOT"
  subject = {
    common_name  = "alpha-dev-device-root"
    organization = "Example"
    country      = "JP"
  }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "root_with_self_signed_install" {
  command = plan

  assert {
    condition     = aws_acmpca_certificate_authority.this.type == "ROOT"
    error_message = "type must be passed through"
  }

  assert {
    condition     = aws_acmpca_certificate_authority.this.usage_mode == "GENERAL_PURPOSE"
    error_message = "usage_mode must default to GENERAL_PURPOSE"
  }

  assert {
    condition     = one(aws_acmpca_certificate_authority.this.certificate_authority_configuration).key_algorithm == "EC_prime256v1"
    error_message = "key_algorithm must default to EC_prime256v1"
  }

  assert {
    condition     = one(aws_acmpca_certificate_authority.this.certificate_authority_configuration).signing_algorithm == "SHA256WITHECDSA"
    error_message = "EC_prime256v1 must sign with SHA256WITHECDSA"
  }

  assert {
    condition     = one(one(aws_acmpca_certificate_authority.this.certificate_authority_configuration).subject).common_name == "alpha-dev-device-root"
    error_message = "The subject must be passed through"
  }

  assert {
    condition     = aws_acmpca_certificate_authority.this.permanent_deletion_time_in_days == 30
    error_message = "permanent_deletion_time_in_days must default to 30"
  }

  assert {
    condition     = length(aws_acmpca_certificate.root) == 1
    error_message = "A ROOT CA must issue its own self-signed certificate"
  }

  assert {
    condition     = aws_acmpca_certificate.root[0].template_arn == "arn:aws:acm-pca:::template/RootCACertificate/V1"
    error_message = "The root certificate must use the RootCACertificate template"
  }

  assert {
    condition     = aws_acmpca_certificate.root[0].certificate_authority_arn == "arn:aws:acm-pca:ap-northeast-1:111111111111:certificate-authority/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The root certificate must be signed by the CA itself"
  }

  assert {
    condition     = aws_acmpca_certificate.root[0].signing_algorithm == "SHA256WITHECDSA"
    error_message = "The root certificate must use the CA signing algorithm"
  }

  assert {
    condition     = one(aws_acmpca_certificate.root[0].validity).type == "YEARS" && one(aws_acmpca_certificate.root[0].validity).value == "10"
    error_message = "Root validity must default to 10 years"
  }

  assert {
    condition     = length(aws_acmpca_certificate_authority_certificate.this) == 1
    error_message = "The self-signed certificate must be installed"
  }
}

run "root_certificate_is_installed_and_output" {
  # Mock apply so the installed certificate and outputs carry the overridden values.
  override_resource {
    target = aws_acmpca_certificate_authority.this
    values = {
      arn                         = "arn:aws:acm-pca:ap-northeast-1:111111111111:certificate-authority/1234abcd-12ab-34cd-56ef-1234567890ab"
      certificate_signing_request = "-----BEGIN CERTIFICATE REQUEST-----\nMIIBmock\n-----END CERTIFICATE REQUEST-----"
    }
  }

  override_resource {
    target = aws_acmpca_certificate.root
    values = {
      certificate       = "-----BEGIN CERTIFICATE-----\nMIIBroot\n-----END CERTIFICATE-----"
      certificate_chain = ""
    }
  }

  assert {
    condition     = aws_acmpca_certificate_authority_certificate.this[0].certificate == "-----BEGIN CERTIFICATE-----\nMIIBroot\n-----END CERTIFICATE-----"
    error_message = "The installed certificate must be the self-signed root"
  }

  assert {
    condition     = output.ca_certificate_pem == "-----BEGIN CERTIFICATE-----\nMIIBroot\n-----END CERTIFICATE-----"
    error_message = "ca_certificate_pem must be the root certificate"
  }

  assert {
    condition     = output.ca_arn == "arn:aws:acm-pca:ap-northeast-1:111111111111:certificate-authority/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "ca_arn output must be the CA ARN"
  }
}

run "revocation_is_never_configured" {
  command = plan

  variables {
    usage_mode = "GENERAL_PURPOSE"
  }

  assert {
    condition     = length(aws_acmpca_certificate_authority.this.revocation_configuration) == 0
    error_message = "CRL and OCSP must stay disabled: no revocation_configuration"
  }
}

run "subordinate_outputs_csr_only" {
  command = plan

  variables {
    type = "SUBORDINATE"
  }

  assert {
    condition     = aws_acmpca_certificate_authority.this.type == "SUBORDINATE"
    error_message = "type must be passed through"
  }

  assert {
    condition     = length(aws_acmpca_certificate.root) == 0
    error_message = "A SUBORDINATE CA must not issue a self-signed certificate"
  }

  assert {
    condition     = length(aws_acmpca_certificate_authority_certificate.this) == 0
    error_message = "Nothing must be installed without a signed certificate"
  }

  assert {
    condition     = output.csr == "-----BEGIN CERTIFICATE REQUEST-----\nMIIBmock\n-----END CERTIFICATE REQUEST-----"
    error_message = "csr output must be the CA certificate signing request"
  }

  assert {
    condition     = output.ca_certificate_pem == null
    error_message = "ca_certificate_pem must be null until a certificate is installed"
  }

  assert {
    condition     = length(aws_acmpca_certificate_authority.this.revocation_configuration) == 0
    error_message = "CRL and OCSP must stay disabled for subordinate CAs too"
  }
}

run "subordinate_installs_given_certificate" {
  command = plan

  variables {
    type = "SUBORDINATE"
    subordinate_certificate = {
      certificate       = "-----BEGIN CERTIFICATE-----\nMIIBsub\n-----END CERTIFICATE-----"
      certificate_chain = "-----BEGIN CERTIFICATE-----\nMIIBparent\n-----END CERTIFICATE-----"
    }
  }

  assert {
    condition     = length(aws_acmpca_certificate.root) == 0
    error_message = "A SUBORDINATE CA must not issue a self-signed certificate"
  }

  assert {
    condition     = aws_acmpca_certificate_authority_certificate.this[0].certificate == "-----BEGIN CERTIFICATE-----\nMIIBsub\n-----END CERTIFICATE-----"
    error_message = "The given signed certificate must be installed"
  }

  assert {
    condition     = aws_acmpca_certificate_authority_certificate.this[0].certificate_chain == "-----BEGIN CERTIFICATE-----\nMIIBparent\n-----END CERTIFICATE-----"
    error_message = "The given chain must be installed"
  }

  assert {
    condition     = output.ca_certificate_pem == "-----BEGIN CERTIFICATE-----\nMIIBsub\n-----END CERTIFICATE-----"
    error_message = "ca_certificate_pem must be the installed subordinate certificate"
  }
}

run "short_lived_usage_mode" {
  command = plan

  variables {
    usage_mode = "SHORT_LIVED_CERTIFICATE"
  }

  assert {
    condition     = aws_acmpca_certificate_authority.this.usage_mode == "SHORT_LIVED_CERTIFICATE"
    error_message = "usage_mode must be passed through"
  }
}

run "signing_algorithm_follows_key_algorithm" {
  command = plan

  variables {
    key_algorithm = "RSA_2048"
  }

  assert {
    condition     = one(aws_acmpca_certificate_authority.this.certificate_authority_configuration).signing_algorithm == "SHA256WITHRSA"
    error_message = "RSA keys must sign with SHA256WITHRSA"
  }
}

run "ec_p384_signs_with_sha384" {
  command = plan

  variables {
    key_algorithm = "EC_secp384r1"
  }

  assert {
    condition     = one(aws_acmpca_certificate_authority.this.certificate_authority_configuration).signing_algorithm == "SHA384WITHECDSA"
    error_message = "EC_secp384r1 must sign with SHA384WITHECDSA"
  }
}

run "deletion_window_boundary_is_accepted" {
  command = plan

  variables {
    permanent_deletion_time_in_days = 7
    validity_years                  = 30
  }

  assert {
    condition     = aws_acmpca_certificate_authority.this.permanent_deletion_time_in_days == 7
    error_message = "7 days must be accepted"
  }

  assert {
    condition     = one(aws_acmpca_certificate.root[0].validity).value == "30"
    error_message = "validity_years must be passed through"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_acmpca_certificate_authority.this.tags["Project"] == "alpha" && aws_acmpca_certificate_authority.this.tags["Name"] == "alpha-dev-device-root"
    error_message = "Name (the subject common name) must be added to the given tags"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "rsa_1024_rejected" {
  command = plan

  variables {
    key_algorithm = "RSA_1024"
  }

  expect_failures = [var.key_algorithm]
}

run "sm2_rejected" {
  command = plan

  variables {
    key_algorithm = "SM2"
  }

  expect_failures = [var.key_algorithm]
}

run "ml_dsa_rejected" {
  command = plan

  variables {
    key_algorithm = "ML_DSA_44"
  }

  expect_failures = [var.key_algorithm]
}

run "deletion_window_below_7_rejected" {
  command = plan

  variables {
    permanent_deletion_time_in_days = 6
  }

  expect_failures = [var.permanent_deletion_time_in_days]
}

run "deletion_window_above_30_rejected" {
  command = plan

  variables {
    permanent_deletion_time_in_days = 31
  }

  expect_failures = [var.permanent_deletion_time_in_days]
}

run "unknown_type_rejected" {
  command = plan

  variables {
    type = "INTERMEDIATE"
  }

  expect_failures = [var.type]
}

run "unknown_usage_mode_rejected" {
  command = plan

  variables {
    usage_mode = "CODE_SIGNING"
  }

  expect_failures = [var.usage_mode]
}

run "root_with_subordinate_certificate_rejected" {
  command = plan

  variables {
    subordinate_certificate = {
      certificate       = "-----BEGIN CERTIFICATE-----\nMIIBsub\n-----END CERTIFICATE-----"
      certificate_chain = "-----BEGIN CERTIFICATE-----\nMIIBparent\n-----END CERTIFICATE-----"
    }
  }

  expect_failures = [var.subordinate_certificate]
}

run "subordinate_certificate_not_pem_rejected" {
  command = plan

  variables {
    type = "SUBORDINATE"
    subordinate_certificate = {
      certificate       = "not a certificate"
      certificate_chain = "-----BEGIN CERTIFICATE-----\nMIIBparent\n-----END CERTIFICATE-----"
    }
  }

  expect_failures = [var.subordinate_certificate]
}

run "validity_zero_rejected" {
  command = plan

  variables {
    validity_years = 0
  }

  expect_failures = [var.validity_years]
}

run "validity_above_30_rejected" {
  command = plan

  variables {
    validity_years = 31
  }

  expect_failures = [var.validity_years]
}

run "empty_common_name_rejected" {
  command = plan

  variables {
    subject = { common_name = "" }
  }

  expect_failures = [var.subject]
}

run "invalid_country_rejected" {
  command = plan

  variables {
    subject = { common_name = "alpha-dev-device-root", country = "JPN" }
  }

  expect_failures = [var.subject]
}
