output "arns" {
  description = "Application inference profile ARNs keyed by the profiles key; pass one as modelId to attribute cost."
  value       = { for k, p in aws_bedrock_inference_profile.this : k => p.arn }
}

output "ids" {
  description = "Application inference profile ids keyed by the profiles key."
  value       = { for k, p in aws_bedrock_inference_profile.this : k => p.id }
}
