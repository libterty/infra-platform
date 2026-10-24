locals {
  log_group_name = "/aws/client-vpn/${var.name}"
}

# Connection logs are not optional: the log group is ours, encrypted with the given key, and the endpoint always writes to it.
resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = local.log_group_name })
}

resource "aws_ec2_client_vpn_endpoint" "this" {
  description            = var.name
  server_certificate_arn = var.server_certificate_arn
  client_cidr_block      = var.client_cidr_block

  vpc_id             = var.vpc_id
  security_group_ids = var.security_group_ids

  split_tunnel          = var.split_tunnel
  dns_servers           = length(var.dns_servers) == 0 ? null : var.dns_servers
  session_timeout_hours = var.session_timeout_hours

  # UDP 443 is fixed; the transport protocol cannot be changed after creation.
  transport_protocol = "udp"
  vpn_port           = 443

  self_service_portal = var.authentication.self_service_saml_provider_arn == null ? "disabled" : "enabled"

  dynamic "authentication_options" {
    for_each = var.authentication.mutual_tls_root_certificate_arn == null ? [] : [var.authentication.mutual_tls_root_certificate_arn]

    content {
      type                       = "certificate-authentication"
      root_certificate_chain_arn = authentication_options.value
    }
  }

  dynamic "authentication_options" {
    for_each = var.authentication.saml_provider_arn == null ? [] : [var.authentication.saml_provider_arn]

    content {
      type                           = "federated-authentication"
      saml_provider_arn              = authentication_options.value
      self_service_saml_provider_arn = var.authentication.self_service_saml_provider_arn
    }
  }

  connection_log_options {
    enabled              = true
    cloudwatch_log_group = aws_cloudwatch_log_group.this.name
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_ec2_client_vpn_network_association" "this" {
  count = length(var.subnet_ids)

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  subnet_id              = var.subnet_ids[count.index]
}

resource "aws_ec2_client_vpn_authorization_rule" "this" {
  count = length(var.authorization_rules)

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  target_network_cidr    = var.authorization_rules[count.index].target_cidr
  description            = var.authorization_rules[count.index].description

  # Exactly one of the two is set: a group rule names the SAML group, otherwise every client is authorized.
  access_group_id      = var.authorization_rules[count.index].access_group_id
  authorize_all_groups = var.authorization_rules[count.index].access_group_id == null ? true : null
}

resource "aws_ec2_client_vpn_route" "this" {
  count = length(var.routes)

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  destination_cidr_block = var.routes[count.index].destination_cidr
  target_vpc_subnet_id   = var.routes[count.index].target_subnet_id
  description            = var.routes[count.index].description

  # A route can only target a subnet that is already associated with the endpoint.
  depends_on = [aws_ec2_client_vpn_network_association.this]
}
