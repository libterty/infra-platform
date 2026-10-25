locals {
  signing_algorithm = {
    EC_prime256v1 = "SHA256WITHECDSA"
    EC_secp384r1  = "SHA384WITHECDSA"
    EC_secp521r1  = "SHA512WITHECDSA"
    RSA_2048      = "SHA256WITHRSA"
    RSA_3072      = "SHA256WITHRSA"
    RSA_4096      = "SHA256WITHRSA"
  }[var.key_algorithm]

  is_root = var.type == "ROOT"
}

resource "aws_acmpca_certificate_authority" "this" {
  type                            = var.type
  usage_mode                      = var.usage_mode
  permanent_deletion_time_in_days = var.permanent_deletion_time_in_days

  certificate_authority_configuration {
    key_algorithm     = var.key_algorithm
    signing_algorithm = local.signing_algorithm

    subject {
      common_name         = var.subject.common_name
      organization        = var.subject.organization
      organizational_unit = var.subject.organizational_unit
      country             = var.subject.country
      state               = var.subject.state
      locality            = var.subject.locality
    }
  }

  # No revocation_configuration: CRL needs an S3 bucket policy for ACM PCA and OCSP is
  # not used by IoT Core; devices are revoked in the IoT registry instead.

  tags = merge(var.tags, { Name = var.subject.common_name })
}

resource "aws_acmpca_certificate" "root" {
  count = local.is_root ? 1 : 0

  certificate_authority_arn   = aws_acmpca_certificate_authority.this.arn
  certificate_signing_request = aws_acmpca_certificate_authority.this.certificate_signing_request
  signing_algorithm           = local.signing_algorithm

  # The partition comes from the CA ARN so the template ARN also works outside aws.
  template_arn = "arn:${split(":", aws_acmpca_certificate_authority.this.arn)[1]}:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = tostring(var.validity_years)
  }
}

resource "aws_acmpca_certificate_authority_certificate" "this" {
  count = local.is_root || var.subordinate_certificate != null ? 1 : 0

  certificate_authority_arn = aws_acmpca_certificate_authority.this.arn
  certificate               = local.is_root ? aws_acmpca_certificate.root[0].certificate : var.subordinate_certificate.certificate
  certificate_chain         = local.is_root ? aws_acmpca_certificate.root[0].certificate_chain : var.subordinate_certificate.certificate_chain
}
