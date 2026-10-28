# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "zone_id" {
  description = "這個環境的 hosted zone ID。"
  value       = module.zone.zone_id
}

output "name_servers" {
  description = "在上層網域建 NS 委派時要填的 name server。"
  value       = module.zone.name_servers
}
