output "arn" {
  description = "元件版本的 ARN。"
  value       = awscc_greengrassv2_component_version.this.arn
}

output "component_name" {
  description = "元件名稱。"
  value       = awscc_greengrassv2_component_version.this.component_name
}

output "component_version" {
  description = "元件版本。部署引用這個 output 時，會等元件版本建好才建部署。"
  value       = awscc_greengrassv2_component_version.this.component_version
}
