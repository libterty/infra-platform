output "guardrail_id" {
  description = "guardrail id。"
  value       = aws_bedrock_guardrail.this.guardrail_id
}

output "guardrail_arn" {
  description = "guardrail ARN。"
  value       = aws_bedrock_guardrail.this.guardrail_arn
}

output "name" {
  description = "guardrail 名稱。"
  value       = aws_bedrock_guardrail.this.name
}

output "version" {
  description = "呼叫端要用的版本，固定 `DRAFT`（不讀 resource 的 `version`），因為這個 module 不發佈版本；對 guardrail 的修改立刻生效。"
  value       = "DRAFT"
}

output "cross_region_profile_arn" {
  description = "`STANDARD` 時是 guardrail profile ARN；`CLASSIC` 時是 `null`。"
  value       = local.cross_region_profile_arn
}

output "cross_region_profile_id" {
  description = "guardrail profile id；`CLASSIC` 時是 `null`。"
  value       = var.cross_region_profile_id
}
