# The thumbprint is left to AWS: for a certificate signed by a trusted root CA (as the EKS issuer is),
# IAM verifies the JWKS endpoint with its own CA library. See the README for the source.
resource "aws_iam_openid_connect_provider" "this" {
  url            = var.issuer_url
  client_id_list = var.client_ids

  tags = var.tags
}
