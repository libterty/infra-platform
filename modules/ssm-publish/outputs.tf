output "names" {
  description = "Published parameter names, keyed by parameter key."
  value = merge(
    { for k, p in aws_ssm_parameter.string : k => p.name },
    { for k, p in aws_ssm_parameter.list : k => p.name },
  )
}

output "arns" {
  description = "Published parameter ARNs, keyed by parameter key."
  value = merge(
    { for k, p in aws_ssm_parameter.string : k => p.arn },
    { for k, p in aws_ssm_parameter.list : k => p.arn },
  )
}
