# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "repository_urls" {
  description = "Repository URL by service name; push images here with a unique tag, never latest."
  value       = { for s, m in module.ecr : s => m.repository_url }
}

output "mirror_repository_urls" {
  description = "Repository URL by mirror name; copy the external image here with the upstream version as the tag."
  value       = { for m, r in module.ecr_mirror : m => r.repository_url }
}
