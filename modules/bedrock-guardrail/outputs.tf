output "guardrail_id" {
  description = "Guardrail id."
  value       = aws_bedrock_guardrail.this.guardrail_id
}

output "guardrail_arn" {
  description = "Guardrail ARN."
  value       = aws_bedrock_guardrail.this.guardrail_arn
}

output "name" {
  description = "Guardrail name."
  value       = aws_bedrock_guardrail.this.name
}

output "version" {
  description = "Version callers must use. Always DRAFT because this module never publishes versions."
  value       = "DRAFT"
}

output "cross_region_profile_arn" {
  description = "Guardrail profile ARN used for STANDARD; null for CLASSIC."
  value       = local.cross_region_profile_arn
}

output "cross_region_profile_id" {
  description = "Guardrail profile id; null for CLASSIC."
  value       = var.cross_region_profile_id
}
