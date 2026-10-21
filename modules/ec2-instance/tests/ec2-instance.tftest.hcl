mock_provider "aws" {
  override_data {
    target = data.aws_ami.al2023
    values = {
      id = "ami-0123456789abcdef0"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "ap-northeast-1"
    }
  }
}

variables {
  name                  = "alpha-dev-app"
  subnet_id             = "subnet-0123456789abcdef0"
  security_group_ids    = ["sg-0123456789abcdef0"]
  instance_profile_name = "alpha-dev-app"
  instance_type         = "t4g.small"
}

run "defaults" {
  command = plan

  assert {
    condition = (
      aws_instance.this.subnet_id == "subnet-0123456789abcdef0" &&
      aws_instance.this.vpc_security_group_ids == toset(["sg-0123456789abcdef0"]) &&
      aws_instance.this.iam_instance_profile == "alpha-dev-app"
    )
    error_message = "Subnet, security groups and instance profile must follow the input"
  }

  assert {
    condition     = aws_instance.this.ami == "ami-0123456789abcdef0"
    error_message = "Without ami_id the instance must use the AMI found by the data source"
  }

  assert {
    condition     = aws_instance.this.disable_api_termination == true
    error_message = "API termination must be disabled by default"
  }

  assert {
    condition     = aws_instance.this.user_data == null
    error_message = "user_data must be null by default"
  }

  assert {
    condition     = aws_instance.this.tags == tomap({ Name = "alpha-dev-app" })
    error_message = "Without tags input the only tag is Name"
  }
}

# ---- AMI ----

run "ami_is_amazon_linux_2023_arm64_by_default" {
  command = plan

  assert {
    condition     = length(data.aws_ami.al2023) == 1 && toset(data.aws_ami.al2023[0].owners) == toset(["amazon"])
    error_message = "The AMI must come from the amazon owner"
  }

  assert {
    condition     = data.aws_ami.al2023[0].most_recent == true
    error_message = "The AMI lookup must pick the most recent image"
  }

  assert {
    condition     = contains(flatten([for f in data.aws_ami.al2023[0].filter : tolist(f.values) if f.name == "name"]), "al2023-ami-2023.*-kernel-*-arm64")
    error_message = "The AMI name filter must select Amazon Linux 2023 for arm64"
  }

  assert {
    condition     = contains(flatten([for f in data.aws_ami.al2023[0].filter : tolist(f.values) if f.name == "architecture"]), "arm64")
    error_message = "The AMI architecture filter must be arm64"
  }
}

run "ami_follows_x86_64_architecture" {
  command = plan

  variables {
    instance_type = "t3.nano"
    architecture  = "x86_64"
  }

  assert {
    condition     = contains(flatten([for f in data.aws_ami.al2023[0].filter : tolist(f.values) if f.name == "name"]), "al2023-ami-2023.*-kernel-*-x86_64")
    error_message = "The AMI name filter must select Amazon Linux 2023 for x86_64"
  }
}

run "explicit_ami_id_skips_the_data_source" {
  command = plan

  variables {
    ami_id = "ami-0fedcba9876543210"
  }

  assert {
    condition     = length(data.aws_ami.al2023) == 0
    error_message = "With ami_id the AMI data source must not be read"
  }

  assert {
    condition     = aws_instance.this.ami == "ami-0fedcba9876543210"
    error_message = "The instance must use ami_id, not the data source value"
  }
}

run "rejects_malformed_ami_id" {
  command = plan

  variables {
    ami_id = "i-0123456789abcdef0"
  }

  expect_failures = [var.ami_id]
}

# ---- security: IMDSv2, no public IP, no key, encryption ----

run "imdsv2_is_required" {
  command = plan

  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required (http_tokens = required)"
  }

  assert {
    condition     = aws_instance.this.metadata_options[0].http_endpoint == "enabled"
    error_message = "The metadata endpoint must stay enabled for SSM and the instance profile"
  }
}

run "metadata_hop_limit_is_one" {
  command = plan

  assert {
    condition     = aws_instance.this.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "The metadata hop limit must be 1"
  }
}

run "no_public_ip" {
  command = plan

  assert {
    condition     = aws_instance.this.associate_public_ip_address == false
    error_message = "associate_public_ip_address must be false, not null"
  }
}

run "root_volume_defaults_are_encrypted_gp3_20" {
  command = plan

  assert {
    condition     = aws_instance.this.root_block_device[0].encrypted == true
    error_message = "The root volume must be encrypted"
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].volume_type == "gp3" && aws_instance.this.root_block_device[0].volume_size == 20
    error_message = "The root volume must default to gp3, 20 GiB"
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].delete_on_termination == true
    error_message = "The root volume must be deleted with the instance"
  }
}

run "root_volume_follows_input_and_stays_encrypted" {
  command = plan

  variables {
    root_volume = {
      size        = 50
      kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    }
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].volume_size == 50
    error_message = "root_volume.size must follow the input"
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].encrypted == true
    error_message = "The root volume must stay encrypted with a custom key"
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    error_message = "root_volume.kms_key_arn must be used as the root volume key"
  }
}

run "root_volume_partial_object_keeps_defaults" {
  command = plan

  variables {
    root_volume = { size = 30 }
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].volume_size == 30
    error_message = "A root_volume with only size must be accepted"
  }
}

run "rejects_root_volume_size_below_ami_snapshot" {
  command = plan

  variables {
    root_volume = { size = 7 }
  }

  expect_failures = [var.root_volume]
}

run "rejects_fractional_root_volume_size" {
  command = plan

  variables {
    root_volume = { size = 20.5 }
  }

  expect_failures = [var.root_volume]
}

run "rejects_root_volume_size_above_limit" {
  command = plan

  variables {
    root_volume = { size = 16385 }
  }

  expect_failures = [var.root_volume]
}

run "rejects_root_volume_kms_key_that_is_not_an_arn" {
  command = plan

  variables {
    root_volume = { kms_key_arn = "alias/aws/ebs" }
  }

  expect_failures = [var.root_volume]
}

run "accepts_root_volume_size_8" {
  command = plan

  variables {
    root_volume = { size = 8 }
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].volume_size == 8
    error_message = "8 GiB must be accepted"
  }
}

# ---- data volumes ----

run "no_ebs_volumes_by_default" {
  command = plan

  assert {
    condition     = length(aws_ebs_volume.this) == 0 && length(aws_volume_attachment.this) == 0
    error_message = "Without ebs_volumes there are no data volumes"
  }
}

run "data_volumes_are_encrypted_and_attached" {
  command = plan

  variables {
    tags = { Project = "alpha" }
    ebs_volumes = {
      data = { device_name = "/dev/sdf", size = 100 }
      logs = {
        device_name = "/dev/sdg"
        size        = 50
        type        = "gp2"
        kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
      }
    }
  }

  assert {
    condition     = alltrue([for v in aws_ebs_volume.this : v.encrypted == true])
    error_message = "Every data volume must be encrypted"
  }

  assert {
    condition     = aws_ebs_volume.this["data"].type == "gp3" && aws_ebs_volume.this["data"].size == 100
    error_message = "A data volume must default to gp3"
  }

  assert {
    condition     = aws_ebs_volume.this["logs"].type == "gp2" && aws_ebs_volume.this["logs"].kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    error_message = "type and kms_key_arn must follow the input"
  }

  assert {
    condition     = aws_volume_attachment.this["data"].device_name == "/dev/sdf" && aws_volume_attachment.this["logs"].device_name == "/dev/sdg"
    error_message = "Each volume must attach at its device_name"
  }

  assert {
    condition     = aws_ebs_volume.this["data"].tags == tomap({ Project = "alpha", Name = "alpha-dev-app-data" })
    error_message = "Data volumes must carry the input tags and a Name of <name>-<key>"
  }
}

run "data_volume_lives_in_the_instance_az_and_attaches_to_it" {
  command = apply

  variables {
    ebs_volumes = {
      data = { device_name = "/dev/sdf", size = 100 }
    }
  }

  assert {
    condition     = aws_ebs_volume.this["data"].availability_zone == aws_instance.this.availability_zone
    error_message = "A data volume must be created in the instance's AZ"
  }

  assert {
    condition     = aws_volume_attachment.this["data"].instance_id == aws_instance.this.id && aws_volume_attachment.this["data"].volume_id == aws_ebs_volume.this["data"].id
    error_message = "The attachment must join the data volume to the instance"
  }
}

run "rejects_data_volume_with_bad_device_name" {
  command = plan

  variables {
    ebs_volumes = { data = { device_name = "sdf", size = 10 } }
  }

  expect_failures = [var.ebs_volumes]
}

run "rejects_data_volume_on_root_device_name" {
  command = plan

  variables {
    ebs_volumes = { data = { device_name = "/dev/sda1", size = 10 } }
  }

  expect_failures = [var.ebs_volumes]
}

run "rejects_duplicate_device_names" {
  command = plan

  variables {
    ebs_volumes = {
      a = { device_name = "/dev/sdf", size = 10 }
      b = { device_name = "/dev/sdf", size = 10 }
    }
  }

  expect_failures = [var.ebs_volumes]
}

run "rejects_data_volume_size_zero" {
  command = plan

  variables {
    ebs_volumes = { data = { device_name = "/dev/sdf", size = 0 } }
  }

  expect_failures = [var.ebs_volumes]
}

run "rejects_unknown_data_volume_type" {
  command = plan

  variables {
    ebs_volumes = { data = { device_name = "/dev/sdf", size = 10, type = "standard" } }
  }

  expect_failures = [var.ebs_volumes]
}

run "rejects_data_volume_kms_key_that_is_not_an_arn" {
  command = plan

  variables {
    ebs_volumes = { data = { device_name = "/dev/sdf", size = 10, kms_key_arn = "my-key" } }
  }

  expect_failures = [var.ebs_volumes]
}

run "rejects_data_volume_key_with_bad_characters" {
  command = plan

  variables {
    ebs_volumes = { "Data Disk" = { device_name = "/dev/sdf", size = 10 } }
  }

  expect_failures = [var.ebs_volumes]
}

# ---- user_data ----

run "user_data_is_passed_through" {
  command = plan

  variables {
    user_data = "#!/bin/bash\ndnf install -y nginx\n"
  }

  assert {
    condition     = aws_instance.this.user_data == "#!/bin/bash\ndnf install -y nginx\n"
    error_message = "user_data must be passed to the instance as given"
  }
}

run "rejects_user_data_that_looks_like_a_secret" {
  command = plan

  variables {
    user_data = "#!/bin/bash\nexport DB_PASSWORD=hunter2\n"
  }

  expect_failures = [var.user_data]
}

run "rejects_user_data_with_lowercase_api_key" {
  command = plan

  variables {
    user_data = "#!/bin/bash\napi_key=abc\n"
  }

  expect_failures = [var.user_data]
}

run "rejects_user_data_over_16kb" {
  command = plan

  variables {
    user_data = join("", [for i in range(1000) : "echo 0123456789abcdef\n"])
  }

  expect_failures = [var.user_data]
}

# ---- termination protection ----

run "termination_protection_can_be_turned_off" {
  command = plan

  variables {
    disable_api_termination = false
  }

  assert {
    condition     = aws_instance.this.disable_api_termination == false
    error_message = "disable_api_termination must follow the input"
  }
}

# ---- system status check alarm (D16) ----

run "no_alarm_without_sns_topics" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.system_status) == 0
    error_message = "With the default empty sns_topic_arns no alarm may be created"
  }
}

run "alarm_outputs_are_empty_without_sns_topics" {
  command = apply

  assert {
    condition     = length(output.alarm_arns) == 0
    error_message = "alarm_arns must be an empty map when no alarm is created"
  }
}

run "alarm_recovers_and_notifies_when_sns_given" {
  command = plan

  variables {
    sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.system_status) == 1
    error_message = "Giving sns_topic_arns must create one alarm"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.system_status[0].metric_name == "StatusCheckFailed_System" && aws_cloudwatch_metric_alarm.system_status[0].namespace == "AWS/EC2"
    error_message = "The alarm must watch AWS/EC2 StatusCheckFailed_System"
  }

  assert {
    condition     = contains(aws_cloudwatch_metric_alarm.system_status[0].alarm_actions, "arn:aws:automate:ap-northeast-1:ec2:recover")
    error_message = "alarm_actions must include the EC2 recover action for the region"
  }

  assert {
    condition     = contains(aws_cloudwatch_metric_alarm.system_status[0].alarm_actions, "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms")
    error_message = "alarm_actions must include the SNS topic"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.system_status[0].ok_actions == toset(["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"])
    error_message = "ok_actions must be the SNS topics only"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.system_status[0].alarm_name == "alpha-dev-app-status-check-system"
    error_message = "Alarm name must be <name>-status-check-system"
  }
}

run "alarm_arns_output_has_the_alarm" {
  command = apply

  variables {
    sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
  }

  assert {
    condition     = length(output.alarm_arns) == 1 && output.alarm_arns["status_check_failed_system"] == aws_cloudwatch_metric_alarm.system_status[0].arn
    error_message = "alarm_arns must map status_check_failed_system to the alarm ARN"
  }
}

run "rejects_sns_topic_that_is_not_an_arn" {
  command = plan

  variables {
    sns_topic_arns = ["alpha-dev-alarms"]
  }

  expect_failures = [var.sns_topic_arns]
}

run "rejects_more_than_four_sns_topics" {
  command = plan

  variables {
    sns_topic_arns = [for i in range(5) : "arn:aws:sns:ap-northeast-1:111111111111:t${i}"]
  }

  expect_failures = [var.sns_topic_arns]
}

run "accepts_four_sns_topics" {
  command = plan

  variables {
    sns_topic_arns = [for i in range(4) : "arn:aws:sns:ap-northeast-1:111111111111:t${i}"]
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.system_status[0].alarm_actions) == 5
    error_message = "Four topics plus recover is the CloudWatch limit of five actions"
  }
}

# ---- outputs and tags ----

run "outputs" {
  command = apply

  assert {
    condition     = output.instance_id == aws_instance.this.id && output.private_ip == aws_instance.this.private_ip
    error_message = "instance_id and private_ip must come from the instance"
  }

  assert {
    condition     = output.ami_id == "ami-0123456789abcdef0"
    error_message = "ami_id must be the AMI found by the data source"
  }
}

run "ami_id_output_follows_explicit_ami" {
  command = apply

  variables {
    ami_id = "ami-0fedcba9876543210"
  }

  assert {
    condition     = output.ami_id == "ami-0fedcba9876543210"
    error_message = "ami_id output must be the given ami_id"
  }
}

run "tags_are_merged_with_name_on_instance_and_root_volume" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_instance.this.tags == tomap({ Project = "alpha", Name = "alpha-dev-app" })
    error_message = "Input tags must be kept and Name added on the instance"
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].tags == tomap({ Project = "alpha", Name = "alpha-dev-app" })
    error_message = "The root volume must carry the same tags"
  }
}

# ---- security_group_ids ----

run "rejects_empty_security_group_ids" {
  command = plan

  variables {
    security_group_ids = []
  }

  expect_failures = [var.security_group_ids]
}

run "rejects_malformed_security_group_id" {
  command = plan

  variables {
    security_group_ids = ["subnet-0123456789abcdef0"]
  }

  expect_failures = [var.security_group_ids]
}

run "accepts_two_security_groups" {
  command = plan

  variables {
    security_group_ids = ["sg-0123456789abcdef0", "sg-0fedcba9876543210"]
  }

  assert {
    condition     = aws_instance.this.vpc_security_group_ids == toset(["sg-0123456789abcdef0", "sg-0fedcba9876543210"])
    error_message = "Several security groups must be accepted"
  }
}

# ---- architecture and instance_type ----

run "rejects_unknown_architecture" {
  command = plan

  variables {
    architecture = "arm"
  }

  expect_failures = [var.architecture]
}

run "rejects_arm64_with_x86_instance_type" {
  command = plan

  variables {
    instance_type = "t3.nano"
  }

  expect_failures = [var.instance_type]
}

run "rejects_x86_64_with_graviton_instance_type" {
  command = plan

  variables {
    instance_type = "t4g.nano"
    architecture  = "x86_64"
  }

  expect_failures = [var.instance_type]
}

run "accepts_x86_64_with_x86_instance_type" {
  command = plan

  variables {
    instance_type = "t3.small"
    architecture  = "x86_64"
  }

  assert {
    condition     = aws_instance.this.instance_type == "t3.small"
    error_message = "An x86 instance type with x86_64 must be accepted"
  }
}

run "accepts_arm64_with_graviton_instance_type" {
  command = plan

  variables {
    instance_type = "c6gn.medium"
  }

  assert {
    condition     = aws_instance.this.instance_type == "c6gn.medium"
    error_message = "A Graviton instance type with arm64 must be accepted"
  }
}

run "accepts_x86_64_with_g4dn_instance_type" {
  command = plan

  variables {
    instance_type = "g4dn.xlarge"
    architecture  = "x86_64"
  }

  assert {
    condition     = aws_instance.this.instance_type == "g4dn.xlarge"
    error_message = "g4dn is x86 and must be accepted with x86_64"
  }
}

run "rejects_instance_type_without_size" {
  command = plan

  variables {
    instance_type = "nano"
  }

  expect_failures = [var.instance_type]
}

# ---- name, subnet, instance profile ----

run "rejects_name_with_uppercase" {
  command = plan

  variables {
    name = "Alpha-app"
  }

  expect_failures = [var.name]
}

run "accepts_lowercase_name" {
  command = plan

  variables {
    name = "alpha-sit-app"
  }

  assert {
    condition     = aws_instance.this.tags["Name"] == "alpha-sit-app"
    error_message = "A lowercase name must be accepted"
  }
}

run "rejects_subnet_id_wrong_prefix" {
  command = plan

  variables {
    subnet_id = "vpc-0123456789abcdef0"
  }

  expect_failures = [var.subnet_id]
}

run "accepts_subnet_id" {
  command = plan

  variables {
    subnet_id = "subnet-0a1b2c3d"
  }

  assert {
    condition     = aws_instance.this.subnet_id == "subnet-0a1b2c3d"
    error_message = "A well-formed subnet id must be accepted"
  }
}

run "rejects_instance_profile_name_with_space" {
  command = plan

  variables {
    instance_profile_name = "alpha app"
  }

  expect_failures = [var.instance_profile_name]
}

run "accepts_instance_profile_name" {
  command = plan

  variables {
    instance_profile_name = "alpha-dev-app_01"
  }

  assert {
    condition     = aws_instance.this.iam_instance_profile == "alpha-dev-app_01"
    error_message = "A valid instance profile name must be accepted"
  }
}

run "allows_user_data_that_fetches_secrets_at_boot" {
  command = plan

  variables {
    user_data = "#!/bin/bash\nTOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token)\nDB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id app/db --query SecretString --output text)\nexport API_KEY=\"$APP_API_KEY\"\n"
  }
}

run "rejects_user_data_with_private_key" {
  command = plan

  variables {
    user_data = "#!/bin/bash\ncat > /root/key <<EOF\n-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXk\n-----END OPENSSH PRIVATE KEY-----\nEOF\n"
  }

  expect_failures = [var.user_data]
}
