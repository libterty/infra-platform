output "instance_id" {
  description = "Instance ID, the target for aws ssm start-session."
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IP address of the instance."
  value       = aws_instance.this.private_ip
}

output "ami_id" {
  description = "AMI the instance was first created from. Later AMI releases are ignored."
  value       = data.aws_ami.al2023.id
}
