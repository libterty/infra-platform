# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "repository_urls" {
  description = "Repository URL by image or Runtime name; push images here with a unique tag, never latest."
  value       = { for key, repo in local.repository : key => repo.url }
}
