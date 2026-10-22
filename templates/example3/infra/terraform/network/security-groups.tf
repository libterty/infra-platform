locals {
  ports = { https = 443, postgres = 5432, redis = 6379, dns = 53 }

  security_groups = {
    alb      = { name = "${local.name_prefix}-alb", description = "Application load balancer" }
    app      = { name = "${local.name_prefix}-app", description = "EKS pods (NodeClass pod security group), ECS tasks and Lambda functions" }
    agent    = { name = "${local.name_prefix}-agent", description = "AgentCore Runtime" }
    db       = { name = "${local.name_prefix}-db", description = "Aurora cluster, reachable only through the RDS Proxy" }
    db_proxy = { name = "${local.name_prefix}-db-proxy", description = "RDS Proxy" }
    cache    = { name = "${local.name_prefix}-cache", description = "ElastiCache clusters" }
    bastion  = { name = "${local.name_prefix}-bastion", description = "Session Manager host; outbound only" }
    # Attached to EKS Auto Mode nodes next to the EKS-created cluster group, whose open egress still applies (design v4 K1).
    node = { name = "${local.name_prefix}-node", description = "EKS Auto Mode nodes" }
    # Extra group on the EKS control plane ENIs: only the runners that run Helm may reach the Kubernetes API.
    eks_api = { name = "${local.name_prefix}-eks-api", description = "Kubernetes API, from the Helm runners only" }
  }

  # Without a NAT, 443 can only reach the interface endpoints in the VPC and S3 through its gateway endpoint.
  no_nat = var.nat_mode == "none"

  alb_ports = [443, 80]

  alb_sources = merge(
    { for c in var.alb_ingress.cidrs : "cidr_${replace(replace(c, ".", "_"), "/", "_")}" => { cidr_ipv4 = c, prefix_list_id = null } },
    { for p in var.alb_ingress.prefix_list_ids : "pl_${replace(p, "-", "_")}" => { cidr_ipv4 = null, prefix_list_id = p } },
  )

  alb_ingress_rules = {
    for pair in setproduct(local.alb_ports, keys(local.alb_sources)) : "alb_in_${pair[0]}_${pair[1]}" => {
      security_group = "alb"
      type           = "ingress"
      description    = pair[0] == 443 ? "clients" : "clients, redirected to https"
      ip_protocol    = "tcp"
      from_port      = pair[0]
      peer_group     = null
      cidr_ipv4      = local.alb_sources[pair[1]].cidr_ipv4
      prefix_list_id = local.alb_sources[pair[1]].prefix_list_id
      allow_internet = local.alb_sources[pair[1]].cidr_ipv4 == "0.0.0.0/0"
    }
  }

  # One entry per allowed connection. Terraform removes the default allow-all egress, so each connection needs an
  # egress rule on the source and an ingress rule on the target.
  connections = concat(
    [
      { from = "alb", to = "app", port = var.app_port },
      { from = "app", to = "db_proxy", port = local.ports.postgres },
      { from = "agent", to = "db_proxy", port = local.ports.postgres },
      { from = "db_proxy", to = "db", port = local.ports.postgres },
      { from = "app", to = "cache", port = local.ports.redis },
      # kubelet on the node probes the api pods; pods query CoreDNS on their own node (UDP 53 is added below).
      { from = "node", to = "app", port = var.app_port },
      { from = "app", to = "node", port = local.ports.dns },
    ],
    var.bastion_enabled ? [
      { from = "bastion", to = "db_proxy", port = local.ports.postgres },
      { from = "bastion", to = "cache", port = local.ports.redis },
    ] : [],
  )

  connection_rules = merge(
    {
      for c in local.connections : "${c.from}_out_${c.to}" => {
        security_group = c.from
        type           = "egress"
        description    = "to ${c.to}"
        ip_protocol    = "tcp"
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
        ip_protocol    = "tcp"
        from_port      = c.port
        peer_group     = c.from
        cidr_ipv4      = null
        prefix_list_id = null
        allow_internet = false
      }
    },
  )

  # DNS also uses UDP; the connection list above is TCP only.
  dns_udp_rules = {
    app_out_node_dns_udp = {
      security_group = "app"
      type           = "egress"
      description    = "CoreDNS on the node, UDP"
      ip_protocol    = "udp"
      from_port      = local.ports.dns
      peer_group     = "node"
      cidr_ipv4      = null
      prefix_list_id = null
      allow_internet = false
    }
    node_in_app_dns_udp = {
      security_group = "node"
      type           = "ingress"
      description    = "CoreDNS for pods, UDP"
      ip_protocol    = "udp"
      from_port      = local.ports.dns
      peer_group     = "app"
      cidr_ipv4      = null
      prefix_list_id = null
      allow_internet = false
    }
  }

  # Runners that run Helm (eks-addons stack, CI) reach the private Kubernetes API through this group (design v4 §7).
  k8s_api_rules = merge(
    { for c in var.k8s_api_sources.cidrs : "eks_api_in_${replace(replace(c, ".", "_"), "/", "_")}" => {
      security_group = "eks_api"
      type           = "ingress"
      description    = "Kubernetes API from a runner network"
      ip_protocol    = "tcp"
      from_port      = local.ports.https
      peer_group     = null
      peer_group_id  = null
      cidr_ipv4      = c
      prefix_list_id = null
      allow_internet = false
    } },
    { for g in var.k8s_api_sources.security_group_ids : "eks_api_in_${replace(g, "-", "_")}" => {
      security_group = "eks_api"
      type           = "ingress"
      description    = "Kubernetes API from a runner group"
      ip_protocol    = "tcp"
      from_port      = local.ports.https
      peer_group     = null
      peer_group_id  = g
      cidr_ipv4      = null
      prefix_list_id = null
      allow_internet = false
    } },
  )

  # Groups that call AWS APIs. Everything else in this stack either only answers or is limited to connections above.
  aws_api_clients = concat(["app", "agent"], var.bastion_enabled ? ["bastion"] : [])

  aws_api_egress_rules = merge(
    {
      for k in local.aws_api_clients : "${k}_out_aws_apis" => {
        security_group = k
        type           = "egress"
        description    = local.no_nat ? "VPC interface endpoints" : "AWS APIs"
        ip_protocol    = "tcp"
        from_port      = local.ports.https
        peer_group     = null
        cidr_ipv4      = local.no_nat ? var.vpc_cidr : "0.0.0.0/0"
        prefix_list_id = null
        allow_internet = false
      }
    },
    {
      for k in local.no_nat ? local.aws_api_clients : [] : "${k}_out_s3" => {
        security_group = k
        type           = "egress"
        description    = "S3 gateway endpoint"
        ip_protocol    = "tcp"
        from_port      = local.ports.https
        peer_group     = null
        cidr_ipv4      = null
        prefix_list_id = data.aws_prefix_list.s3.id
        allow_internet = false
      }
    },
  )

  # The app group holds the ECS tasks and the Lambda functions, which are the ones that call the peer network.
  peering_egress_rules = {
    for c in var.peering == null ? [] : var.peering.peer_cidrs : "app_out_peer_${replace(replace(c, ".", "_"), "/", "_")}" => {
      security_group = "app"
      type           = "egress"
      description    = "peer network over the peering connection"
      ip_protocol    = "tcp"
      from_port      = local.ports.https
      peer_group     = null
      cidr_ipv4      = c
      prefix_list_id = null
      allow_internet = false
    }
  }

  sg_rules = merge(local.alb_ingress_rules, local.connection_rules, local.dns_udp_rules, local.k8s_api_rules, local.aws_api_egress_rules, local.peering_egress_rules)
}

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.aws_region}.s3"
}

module "sg" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/security-group/aws"
  version = "~> 0.1.0"

  vpc_id          = module.vpc.vpc_id
  security_groups = local.security_groups
  rules           = local.sg_rules
}
