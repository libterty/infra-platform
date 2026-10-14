resource "aws_flow_log" "this" {
  count = var.flow_log == null ? 0 : 1

  vpc_id               = aws_vpc.this.id
  log_destination      = var.flow_log.destination_arn
  log_destination_type = "s3"
  traffic_type         = var.flow_log.traffic_type

  tags = merge(var.tags, { Name = var.name })
}
