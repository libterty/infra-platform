output "arns" {
  description = "key 同 `profiles` 的 map，值是 application inference profile ARN；呼叫端把它當 `modelId` 傳，費用才會歸到這個 profile。"
  value       = { for k, p in aws_bedrock_inference_profile.this : k => p.arn }
}

output "ids" {
  description = "key 同 `profiles` 的 map，值是 application inference profile id。"
  value       = { for k, p in aws_bedrock_inference_profile.this : k => p.id }
}
