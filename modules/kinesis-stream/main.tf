resource "aws_kinesis_stream" "this" {
  name             = var.name
  shard_count      = var.shard_count
  retention_period = var.retention_hours

  # Encryption is not optional: the key is a required input and the type is fixed.
  encryption_type = "KMS"
  kms_key_id      = var.kms_key_arn

  shard_level_metrics = var.shard_level_metrics

  stream_mode_details {
    stream_mode = var.mode
  }

  tags = merge(var.tags, { Name = var.name })
}
