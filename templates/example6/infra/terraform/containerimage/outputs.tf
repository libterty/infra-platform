# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "api_repository_url" {
  description = "API Lambda 映像的 repository URL；推映像時用唯一的 tag，不要用 latest。"
  value       = module.api_repository.repository_url
}
