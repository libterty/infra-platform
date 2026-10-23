output "instance_id" {
  description = "instance ID，`aws ssm start-session` 的 target。"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "instance 的私有 IP。"
  value       = aws_instance.this.private_ip
}

output "ami_id" {
  description = "目前查到的最新 Amazon Linux 2023 AMI。因為 `ignore_changes = [ami]`，不一定是這台實際在用的。"
  value       = data.aws_ami.al2023.id
}
