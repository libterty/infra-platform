output "zone_id" {
  description = "hosted zone ID，`route53-record` 與 `acm-certificate` 的 `zone_id` 用這個值。"
  value       = aws_route53_zone.this.zone_id
}

output "name" {
  description = "zone 的網域名稱（結尾不帶 `.`）。"
  value       = aws_route53_zone.this.name
}

output "name_servers" {
  description = "public zone 的 name server，拿去在上層網域建 NS 委派；private zone 時是空 list。"
  value       = length(var.private_vpc_ids) > 0 ? [] : aws_route53_zone.this.name_servers
}

output "arn" {
  description = "zone 的 ARN。"
  value       = aws_route53_zone.this.arn
}
