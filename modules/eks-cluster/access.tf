locals {
  access_policy_arn_prefix = "arn:aws:eks::aws:cluster-access-policy"

  # One association per (entry, policy) pair.
  access_policy_associations = merge([
    for entry_key, entry in var.access_entries : {
      for policy_key, p in entry.policies : "${entry_key}/${policy_key}" => {
        entry_key  = entry_key
        policy     = p.policy
        namespaces = p.namespaces
      }
    }
  ]...)
}

resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  type          = each.value.type

  tags = local.tags
}

resource "aws_eks_access_policy_association" "this" {
  for_each = local.access_policy_associations

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.this[each.value.entry_key].principal_arn
  policy_arn    = "${local.access_policy_arn_prefix}/${each.value.policy}"

  access_scope {
    type       = length(each.value.namespaces) == 0 ? "cluster" : "namespace"
    namespaces = length(each.value.namespaces) == 0 ? null : each.value.namespaces
  }
}

resource "aws_eks_pod_identity_association" "this" {
  for_each = var.pod_identity_associations

  cluster_name    = aws_eks_cluster.this.name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = each.value.role_arn

  tags = local.tags
}
