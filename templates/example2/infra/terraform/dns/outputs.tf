# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "name_servers" {
  description = "Name servers of the zone. Add them as an NS record for zone_name in the parent zone before applying certificate."
  value       = module.zone.name_servers
}
