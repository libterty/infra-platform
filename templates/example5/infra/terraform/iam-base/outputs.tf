# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "role_arns" {
  description = "Role ARN，key 為 iot_rule、iot_provisioning、iot_logging、iot_audit、iot_mitigation、greengrass_tes、ota_presign、firehose、sagemaker_pipeline、sagemaker_endpoint、scheduler。"
  value       = { for k, m in module.role : k => m.arn }
}
