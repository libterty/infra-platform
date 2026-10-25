# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "thing_group_arns" {
  description = "thing group 名稱對應 ARN。"
  value       = module.fleet.thing_group_arns
}

output "policy_names" {
  description = "IoT policy 名稱：裝置、core device、claim 憑證各一份。claim 憑證在 Terraform 外用 CSR 建立後，附加 claim policy。"
  value       = module.fleet.policy_names
}

output "provisioning_template_name" {
  description = "fleet provisioning template 名稱。"
  value       = module.fleet.provisioning_template_name
}
