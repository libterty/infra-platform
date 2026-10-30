# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "api_repository_url" {
  description = "api（ECS）映像的 repository URL；第一版映像要在 apply `application` 之前手動推，用唯一的 tag，不要用 latest。"
  value       = module.repository["api"].repository_url
}

output "fn_repository_url" {
  description = "fn（Lambda）映像的 repository URL；第一版映像要在 apply `application` 之前手動推，用唯一的 tag，不要用 latest。"
  value       = module.repository["fn"].repository_url
}
