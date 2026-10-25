mock_provider "aws" {}

variables {
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  streams = {
    alpha-dev-cam-01 = {
      retention_hours = 48
      device_name     = "alpha-dev-core-01"
    }
    alpha-dev-cam-02 = {}
  }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "multiple_streams_with_defaults" {
  command = plan

  assert {
    condition     = length(aws_kinesis_video_stream.this) == 2
    error_message = "One stream must be created per map entry"
  }

  assert {
    condition     = aws_kinesis_video_stream.this["alpha-dev-cam-01"].name == "alpha-dev-cam-01"
    error_message = "The map key must be the stream name"
  }

  assert {
    condition     = aws_kinesis_video_stream.this["alpha-dev-cam-01"].data_retention_in_hours == 48 && aws_kinesis_video_stream.this["alpha-dev-cam-01"].device_name == "alpha-dev-core-01"
    error_message = "retention_hours and device_name must be passed through"
  }

  assert {
    condition     = aws_kinesis_video_stream.this["alpha-dev-cam-02"].data_retention_in_hours == 24
    error_message = "retention_hours must default to 24"
  }

  assert {
    condition     = aws_kinesis_video_stream.this["alpha-dev-cam-02"].media_type == "video/h264"
    error_message = "media_type must default to video/h264"
  }

  assert {
    condition     = aws_kinesis_video_stream.this["alpha-dev-cam-02"].device_name == null
    error_message = "device_name must be null when not given"
  }
}

run "every_stream_uses_the_given_key" {
  command = plan

  assert {
    condition     = alltrue([for s in aws_kinesis_video_stream.this : s.kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"])
    error_message = "Every stream must be encrypted with the given customer managed key"
  }
}

run "retention_boundaries_are_accepted" {
  command = plan

  variables {
    streams = {
      alpha-dev-live    = { retention_hours = 0 }
      alpha-dev-archive = { retention_hours = 87600 }
    }
  }

  assert {
    condition     = aws_kinesis_video_stream.this["alpha-dev-live"].data_retention_in_hours == 0 && aws_kinesis_video_stream.this["alpha-dev-archive"].data_retention_in_hours == 87600
    error_message = "0 and 87600 hours must be accepted"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_kinesis_video_stream.this["alpha-dev-cam-01"].tags["Project"] == "alpha" && aws_kinesis_video_stream.this["alpha-dev-cam-01"].tags["Name"] == "alpha-dev-cam-01"
    error_message = "Name must be added to the given tags"
  }
}

run "empty_map_creates_nothing" {
  command = plan

  variables {
    streams = {}
  }

  assert {
    condition     = length(aws_kinesis_video_stream.this) == 0 && length(output.stream_names) == 0 && length(output.stream_arns) == 0
    error_message = "An empty map must create no streams"
  }
}

run "outputs_after_apply" {
  override_resource {
    target = aws_kinesis_video_stream.this["alpha-dev-cam-01"]
    values = {
      arn = "arn:aws:kinesisvideo:ap-northeast-1:111111111111:stream/alpha-dev-cam-01/1700000000000"
    }
  }

  assert {
    condition     = join(",", output.stream_names) == "alpha-dev-cam-01,alpha-dev-cam-02"
    error_message = "stream_names must be the sorted stream names"
  }

  assert {
    condition     = output.stream_arns["alpha-dev-cam-01"] == "arn:aws:kinesisvideo:ap-northeast-1:111111111111:stream/alpha-dev-cam-01/1700000000000"
    error_message = "stream_arns must map stream names to ARNs"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "retention_above_87600_rejected" {
  command = plan

  variables {
    streams = { alpha-dev-cam-01 = { retention_hours = 87601 } }
  }

  expect_failures = [var.streams]
}

run "negative_retention_rejected" {
  command = plan

  variables {
    streams = { alpha-dev-cam-01 = { retention_hours = -1 } }
  }

  expect_failures = [var.streams]
}

run "fractional_retention_rejected" {
  command = plan

  variables {
    streams = { alpha-dev-cam-01 = { retention_hours = 1.5 } }
  }

  expect_failures = [var.streams]
}

run "invalid_stream_name_rejected" {
  command = plan

  variables {
    streams = { "alpha dev/cam" = {} }
  }

  expect_failures = [var.streams]
}

run "invalid_device_name_rejected" {
  command = plan

  variables {
    streams = { alpha-dev-cam-01 = { device_name = "core 01" } }
  }

  expect_failures = [var.streams]
}

run "invalid_media_type_rejected" {
  command = plan

  variables {
    streams = { alpha-dev-cam-01 = { media_type = "h264" } }
  }

  expect_failures = [var.streams]
}

run "kms_key_arn_is_required" {
  command = plan

  variables {
    kms_key_arn = null
  }

  expect_failures = [var.kms_key_arn]
}

run "kms_alias_arn_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev"
  }

  expect_failures = [var.kms_key_arn]
}
