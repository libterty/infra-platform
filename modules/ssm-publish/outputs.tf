output "names" {
  description = "已發布的參數名稱，key 為參數 key。"
  value = merge(
    { for k, p in aws_ssm_parameter.string : k => p.name },
    { for k, p in aws_ssm_parameter.list : k => p.name },
  )
}

output "arns" {
  description = "已發布的參數 ARN，key 為參數 key；apply 前是 unknown。"
  value = merge(
    { for k, p in aws_ssm_parameter.string : k => p.arn },
    { for k, p in aws_ssm_parameter.list : k => p.arn },
  )
}
