resource "aws_kinesis_video_stream" "this" {
  for_each = var.streams

  name                    = each.key
  data_retention_in_hours = each.value.retention_hours
  media_type              = each.value.media_type
  device_name             = each.value.device_name

  # Encryption with a customer managed key is not optional: the key is a required input.
  kms_key_id = var.kms_key_arn

  tags = merge(var.tags, { Name = each.key })
}
