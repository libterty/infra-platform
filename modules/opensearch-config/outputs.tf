output "ism_policy_ids" {
  description = "ISM policy id，依 key 排序。"
  value       = [for k in sort(keys(opensearch_ism_policy.this)) : opensearch_ism_policy.this[k].policy_id]
}

output "writer_role_names" {
  description = "寫入用 FGAC role 的名稱，依 key 排序。"
  value       = [for k in sort(keys(opensearch_role.writer)) : opensearch_role.writer[k].role_name]
}
