output "repository_urls" {
  description = "Repository URL by service name; push images here with a unique tag, never latest."
  value       = { for s, m in module.ecr : s => m.repository_url }
}
