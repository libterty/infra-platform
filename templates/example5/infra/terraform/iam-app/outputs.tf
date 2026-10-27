# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
# iam-app publishes no SSM key (design section 7.2): it only attaches policies to roles of iam-base.
output "firehose_policy_names" {
  description = "附加在 iam-base 建立的 firehose role 上的 inline policy 名稱。"
  value       = module.firehose_policy.policy_names
}
