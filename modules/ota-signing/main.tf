resource "aws_signer_signing_profile" "this" {
  name        = var.name
  platform_id = var.platform_id

  # signature_validity_period is left out: AWS documents it as applying only to the
  # Lambda and Notation platforms, and the module only accepts IoT platforms.

  signing_material {
    certificate_arn = var.certificate_arn
  }

  signing_parameters = length(var.signing_parameters) > 0 ? var.signing_parameters : null

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_signer_signing_profile_permission" "start_job" {
  for_each = var.start_job_principals

  profile_name = aws_signer_signing_profile.this.name
  action       = "signer:StartSigningJob"
  principal    = each.value
}
