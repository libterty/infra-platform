locals {
  # SG keys are snake_case; the name uses hyphens. Descriptions are English because EC2 rejects non-ASCII ones.
  security_groups = {
    opensearch   = { name = "${local.name_prefix}-opensearch", description = "OpenSearch domain" }
    firehose     = { name = "${local.name_prefix}-firehose", description = "Firehose delivery to OpenSearch" }
    redshift     = { name = "${local.name_prefix}-redshift", description = "Redshift warehouse" }
    quicksight   = { name = "${local.name_prefix}-quicksight", description = "QuickSight VPC connection" }
    client_vpn   = { name = "${local.name_prefix}-client-vpn", description = "Client VPN endpoint" }
    search_admin = { name = "${local.name_prefix}-search-admin", description = "Runner of the search-config stack" }
  }

  # One entry per allowed connection: from -> to on port. OpenSearch and Redshift only ever receive. Security groups are
  # stateful but Terraform removes the default allow-all egress, so each connection needs an egress rule on the source
  # and an ingress rule on the target.
  connections = [
    { from = "firehose", to = "opensearch", port = 443 },
    { from = "client_vpn", to = "opensearch", port = 443 },
    { from = "client_vpn", to = "redshift", port = 5439 },
    { from = "quicksight", to = "redshift", port = 5439 },
    { from = "search_admin", to = "opensearch", port = 443 },
  ]

  sg_rules = merge(
    {
      for c in local.connections : "${c.from}_out_${c.to}" => {
        security_group = c.from
        type           = "egress"
        description    = "to ${c.to}"
        from_port      = c.port
        peer_group     = c.to
        cidr_ipv4      = null
        prefix_list_id = null
        allow_internet = false
      }
    },
    {
      for c in local.connections : "${c.to}_in_${c.from}" => {
        security_group = c.to
        type           = "ingress"
        description    = "from ${c.from}"
        from_port      = c.port
        peer_group     = c.from
        cidr_ipv4      = null
        prefix_list_id = null
        allow_internet = false
      }
    },
  )
}

module "sg" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/security-group/aws"
  version = "~> 0.1.1"

  vpc_id          = module.vpc.vpc_id
  security_groups = local.security_groups
  rules           = local.sg_rules
}
