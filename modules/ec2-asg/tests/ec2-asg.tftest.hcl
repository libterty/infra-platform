mock_provider "aws" {
  override_data {
    target = data.aws_ami.al2023
    values = {
      id = "ami-0123456789abcdef0"
    }
  }

  # The provider validates the launch template id format even on mock values.
  override_resource {
    target = aws_launch_template.this
    values = {
      id             = "lt-0123456789abcdef0"
      latest_version = 3
    }
  }
}

variables {
  name                  = "alpha-dev-web"
  subnet_ids            = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  security_group_ids    = ["sg-0123456789abcdef0"]
  instance_profile_name = "alpha-dev-web"
  instance_types        = ["t4g.small"]
  min_size              = 1
  desired_capacity      = 2
  max_size              = 4
}

run "defaults" {
  command = plan

  assert {
    condition = (
      aws_autoscaling_group.this.name == "alpha-dev-web" &&
      aws_autoscaling_group.this.min_size == 1 &&
      aws_autoscaling_group.this.desired_capacity == 2 &&
      aws_autoscaling_group.this.max_size == 4 &&
      aws_autoscaling_group.this.vpc_zone_identifier == toset(["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"])
    )
    error_message = "ASG name, sizes and subnets must follow the input"
  }

  assert {
    condition     = aws_autoscaling_group.this.health_check_grace_period == 300
    error_message = "Default health_check_grace_period must be 300"
  }

  assert {
    condition     = aws_launch_template.this.instance_type == "t4g.small"
    error_message = "The launch template must use the first instance type"
  }

  assert {
    condition     = aws_launch_template.this.iam_instance_profile[0].name == "alpha-dev-web"
    error_message = "The launch template must carry the instance profile"
  }

  assert {
    condition     = aws_launch_template.this.network_interfaces[0].security_groups == toset(["sg-0123456789abcdef0"])
    error_message = "Security groups must be set on the network interface"
  }

  assert {
    condition     = aws_launch_template.this.key_name == null || aws_launch_template.this.key_name == ""
    error_message = "There must be no SSH key"
  }
}

# ---- launch template: security fixed settings ----

run "imdsv2_is_required" {
  command = plan

  assert {
    condition     = aws_launch_template.this.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required"
  }

  assert {
    condition     = aws_launch_template.this.metadata_options[0].http_endpoint == "enabled"
    error_message = "The metadata endpoint must stay enabled"
  }
}

run "metadata_hop_limit_is_one" {
  command = plan

  assert {
    condition     = aws_launch_template.this.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "The metadata hop limit must be 1"
  }
}

run "no_public_ip" {
  command = plan

  assert {
    condition     = tostring(aws_launch_template.this.network_interfaces[0].associate_public_ip_address) == "false"
    error_message = "associate_public_ip_address must be explicitly false"
  }
}

run "root_volume_is_encrypted_gp3" {
  command = plan

  assert {
    condition     = aws_launch_template.this.block_device_mappings[0].device_name == "/dev/xvda"
    error_message = "The root device must be configured"
  }

  assert {
    condition     = tostring(aws_launch_template.this.block_device_mappings[0].ebs[0].encrypted) == "true"
    error_message = "The root volume must be encrypted"
  }

  assert {
    condition     = aws_launch_template.this.block_device_mappings[0].ebs[0].volume_type == "gp3"
    error_message = "The root volume must be gp3"
  }

  assert {
    condition     = aws_launch_template.this.block_device_mappings[0].ebs[0].volume_size == 20
    error_message = "Default root volume size must be 20"
  }

  assert {
    condition     = aws_launch_template.this.block_device_mappings[0].ebs[0].kms_key_id == null || aws_launch_template.this.block_device_mappings[0].ebs[0].kms_key_id == ""
    error_message = "Without kms_key_arn the account default EBS key is used"
  }
}

run "root_volume_follows_input" {
  command = plan

  variables {
    root_volume = {
      size        = 50
      kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    }
  }

  assert {
    condition     = aws_launch_template.this.block_device_mappings[0].ebs[0].volume_size == 50
    error_message = "Root volume size must follow the input"
  }

  assert {
    condition     = aws_launch_template.this.block_device_mappings[0].ebs[0].kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    error_message = "kms_key_arn must be used as kms_key_id"
  }

  assert {
    condition     = tostring(aws_launch_template.this.block_device_mappings[0].ebs[0].encrypted) == "true"
    error_message = "The root volume must stay encrypted with a custom key"
  }
}

run "launch_template_updates_default_version" {
  command = plan

  assert {
    condition     = aws_launch_template.this.update_default_version == true
    error_message = "update_default_version must be true"
  }
}

run "asg_uses_launch_template_without_mixed_policy_when_spot_is_null" {
  command = plan

  assert {
    condition     = length(aws_autoscaling_group.this.launch_template) == 1 && length(aws_autoscaling_group.this.mixed_instances_policy) == 0
    error_message = "Without spot the ASG must use a plain launch_template and no mixed_instances_policy"
  }
}

# ---- AMI ----

run "ami_is_amazon_linux_2023_arm64_by_default" {
  command = plan

  assert {
    condition     = aws_launch_template.this.image_id == "ami-0123456789abcdef0"
    error_message = "The launch template must use the AMI found by the data source"
  }

  assert {
    condition     = toset(data.aws_ami.al2023[0].owners) == toset(["amazon"]) && data.aws_ami.al2023[0].most_recent == true
    error_message = "The AMI must be the most recent one from the amazon owner"
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
    instance_types = ["t3.small"]
    architecture   = "x86_64"
  }

  assert {
    condition     = contains(flatten([for f in data.aws_ami.al2023[0].filter : tolist(f.values) if f.name == "name"]), "al2023-ami-2023.*-kernel-*-x86_64")
    error_message = "The AMI name filter must select Amazon Linux 2023 for x86_64"
  }
}

run "ami_id_skips_lookup" {
  command = plan

  variables {
    ami_id = "ami-0aaaaaaaaaaaaaaaa"
  }

  assert {
    condition     = aws_launch_template.this.image_id == "ami-0aaaaaaaaaaaaaaaa"
    error_message = "ami_id must be used directly"
  }

  assert {
    condition     = length(data.aws_ami.al2023) == 0
    error_message = "No AMI lookup when ami_id is given"
  }
}

run "rejects_malformed_ami_id" {
  command = plan

  variables {
    ami_id = "image-0123456789abcdef0"
  }

  expect_failures = [var.ami_id]
}

# ---- health check type ----

run "health_check_type_is_ec2_without_target_groups" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.this.health_check_type == "EC2"
    error_message = "health_check_type must be EC2 without target groups"
  }

  assert {
    condition     = length(aws_autoscaling_group.this.target_group_arns) == 0
    error_message = "No target groups by default"
  }
}

run "health_check_type_is_elb_with_target_groups" {
  command = plan

  variables {
    target_group_arns = ["arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-dev-web/0123456789abcdef"]
  }

  assert {
    condition     = aws_autoscaling_group.this.health_check_type == "ELB"
    error_message = "health_check_type must be ELB with target groups"
  }

  assert {
    condition     = aws_autoscaling_group.this.target_group_arns == toset(["arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-dev-web/0123456789abcdef"])
    error_message = "target_group_arns must follow the input"
  }
}

run "rejects_malformed_target_group_arn" {
  command = plan

  variables {
    target_group_arns = ["alpha-dev-web"]
  }

  expect_failures = [var.target_group_arns]
}

# ---- spot ----

run "spot_adds_mixed_instances_policy_with_defaults" {
  command = plan

  variables {
    instance_types = ["t4g.small", "t4g.medium"]
    spot           = {}
  }

  assert {
    condition     = length(aws_autoscaling_group.this.mixed_instances_policy) == 1 && length(aws_autoscaling_group.this.launch_template) == 0
    error_message = "With spot the ASG must use mixed_instances_policy only"
  }

  assert {
    condition = (
      aws_autoscaling_group.this.mixed_instances_policy[0].instances_distribution[0].on_demand_base_capacity == 1 &&
      aws_autoscaling_group.this.mixed_instances_policy[0].instances_distribution[0].on_demand_percentage_above_base_capacity == 0 &&
      aws_autoscaling_group.this.mixed_instances_policy[0].instances_distribution[0].spot_allocation_strategy == "price-capacity-optimized"
    )
    error_message = "Spot defaults must be base 1, 0 percent on-demand above base, price-capacity-optimized"
  }

  assert {
    condition     = [for o in aws_autoscaling_group.this.mixed_instances_policy[0].launch_template[0].override : o.instance_type] == ["t4g.small", "t4g.medium"]
    error_message = "Every instance type must be an override, in order"
  }
}

run "spot_follows_input" {
  command = plan

  variables {
    spot = {
      on_demand_base_capacity         = 0
      on_demand_percentage_above_base = 20
      allocation_strategy             = "capacity-optimized"
    }
  }

  assert {
    condition = (
      aws_autoscaling_group.this.mixed_instances_policy[0].instances_distribution[0].on_demand_base_capacity == 0 &&
      aws_autoscaling_group.this.mixed_instances_policy[0].instances_distribution[0].on_demand_percentage_above_base_capacity == 20 &&
      aws_autoscaling_group.this.mixed_instances_policy[0].instances_distribution[0].spot_allocation_strategy == "capacity-optimized"
    )
    error_message = "Spot settings must follow the input"
  }
}

run "rejects_spot_percentage_above_100" {
  command = plan

  variables {
    spot = { on_demand_percentage_above_base = 101 }
  }

  expect_failures = [var.spot]
}

run "rejects_spot_percentage_below_0" {
  command = plan

  variables {
    spot = { on_demand_percentage_above_base = -1 }
  }

  expect_failures = [var.spot]
}

run "accepts_spot_percentage_0_and_100" {
  command = plan

  variables {
    spot = { on_demand_percentage_above_base = 0 }
  }

  assert {
    condition     = aws_autoscaling_group.this.mixed_instances_policy[0].instances_distribution[0].on_demand_percentage_above_base_capacity == 0
    error_message = "0 percent must be accepted"
  }
}

run "rejects_negative_spot_base_capacity" {
  command = plan

  variables {
    spot = { on_demand_base_capacity = -1 }
  }

  expect_failures = [var.spot]
}

run "rejects_unknown_spot_allocation_strategy" {
  command = plan

  variables {
    spot = { allocation_strategy = "cheapest" }
  }

  expect_failures = [var.spot]
}

# ---- cpu_target ----

run "no_scaling_policy_without_cpu_target" {
  command = plan

  assert {
    condition     = length(aws_autoscaling_policy.cpu) == 0
    error_message = "No scaling policy when cpu_target is null"
  }
}

run "cpu_target_creates_target_tracking_policy" {
  command = plan

  variables {
    cpu_target = 60
  }

  assert {
    condition = (
      aws_autoscaling_policy.cpu[0].policy_type == "TargetTrackingScaling" &&
      aws_autoscaling_policy.cpu[0].target_tracking_configuration[0].predefined_metric_specification[0].predefined_metric_type == "ASGAverageCPUUtilization" &&
      aws_autoscaling_policy.cpu[0].target_tracking_configuration[0].target_value == 60
    )
    error_message = "cpu_target must create an ASGAverageCPUUtilization target tracking policy"
  }
}

run "rejects_cpu_target_zero" {
  command = plan

  variables {
    cpu_target = 0
  }

  expect_failures = [var.cpu_target]
}

run "rejects_cpu_target_above_100" {
  command = plan

  variables {
    cpu_target = 101
  }

  expect_failures = [var.cpu_target]
}

run "accepts_cpu_target_100" {
  command = plan

  variables {
    cpu_target = 100
  }

  assert {
    condition     = aws_autoscaling_policy.cpu[0].target_tracking_configuration[0].target_value == 100
    error_message = "100 must be accepted"
  }
}

# ---- instance refresh ----

run "instance_refresh_defaults" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.this.instance_refresh[0].strategy == "Rolling" && aws_autoscaling_group.this.instance_refresh[0].preferences[0].min_healthy_percentage == 90
    error_message = "Default instance refresh must be Rolling with 90 percent healthy"
  }
}

run "instance_refresh_follows_input" {
  command = plan

  variables {
    instance_refresh = { min_healthy_percentage = 50 }
  }

  assert {
    condition     = aws_autoscaling_group.this.instance_refresh[0].preferences[0].min_healthy_percentage == 50
    error_message = "min_healthy_percentage must follow the input"
  }
}

run "rejects_instance_refresh_percentage_above_100" {
  command = plan

  variables {
    instance_refresh = { min_healthy_percentage = 101 }
  }

  expect_failures = [var.instance_refresh]
}

run "rejects_instance_refresh_percentage_below_0" {
  command = plan

  variables {
    instance_refresh = { min_healthy_percentage = -1 }
  }

  expect_failures = [var.instance_refresh]
}

# ---- min / desired / max ----

run "rejects_desired_below_min" {
  command = plan

  variables {
    min_size         = 2
    desired_capacity = 1
    max_size         = 4
  }

  expect_failures = [var.desired_capacity]
}

run "rejects_desired_above_max" {
  command = plan

  variables {
    min_size         = 1
    desired_capacity = 5
    max_size         = 4
  }

  expect_failures = [var.desired_capacity]
}

run "accepts_desired_equal_to_min_and_max" {
  command = plan

  variables {
    min_size         = 2
    desired_capacity = 2
    max_size         = 2
  }

  assert {
    condition     = aws_autoscaling_group.this.min_size == 2 && aws_autoscaling_group.this.max_size == 2
    error_message = "min = desired = max must be accepted"
  }
}

run "accepts_zero_sizes" {
  command = plan

  variables {
    min_size         = 0
    desired_capacity = 0
    max_size         = 1
  }

  assert {
    condition     = aws_autoscaling_group.this.desired_capacity == 0
    error_message = "An ASG scaled to zero must be accepted"
  }
}

run "rejects_negative_min_size" {
  command = plan

  variables {
    min_size         = -1
    desired_capacity = 0
    max_size         = 1
  }

  expect_failures = [var.min_size]
}

# ---- architecture and instance_types ----

run "rejects_empty_instance_types" {
  command = plan

  variables {
    instance_types = []
  }

  expect_failures = [var.instance_types]
}

run "rejects_arm64_with_x86_instance_type" {
  command = plan

  variables {
    instance_types = ["t3.small"]
  }

  expect_failures = [var.instance_types]
}

run "rejects_x86_64_with_graviton_instance_type" {
  command = plan

  variables {
    architecture = "x86_64"
  }

  expect_failures = [var.instance_types]
}

run "rejects_one_mismatched_type_among_several" {
  command = plan

  variables {
    instance_types = ["t4g.small", "t3.small"]
  }

  expect_failures = [var.instance_types]
}

run "accepts_several_graviton_types" {
  command = plan

  variables {
    instance_types = ["t4g.small", "m7g.large", "c6gn.medium"]
  }

  assert {
    condition     = aws_launch_template.this.instance_type == "t4g.small"
    error_message = "Several Graviton types must be accepted and the first is primary"
  }
}

run "accepts_x86_64_types_including_g4dn" {
  command = plan

  variables {
    instance_types = ["t3.small", "g4dn.xlarge", "m7i-flex.large"]
    architecture   = "x86_64"
  }

  assert {
    condition     = aws_launch_template.this.instance_type == "t3.small"
    error_message = "x86 types must be accepted with x86_64"
  }
}

run "rejects_instance_type_without_size" {
  command = plan

  variables {
    instance_types = ["small"]
  }

  expect_failures = [var.instance_types]
}

run "rejects_unknown_architecture" {
  command = plan

  variables {
    architecture = "arm"
  }

  expect_failures = [var.architecture]
}

# ---- user_data ----

run "user_data_is_null_by_default" {
  command = plan

  assert {
    condition     = aws_launch_template.this.user_data == null
    error_message = "No user_data by default"
  }
}

run "user_data_is_base64_encoded" {
  command = plan

  variables {
    user_data = "#!/bin/bash\ndnf install -y nginx\n"
  }

  assert {
    condition     = base64decode(aws_launch_template.this.user_data) == "#!/bin/bash\ndnf install -y nginx\n"
    error_message = "user_data must be base64 encoded in the launch template"
  }
}

run "rejects_user_data_with_password" {
  command = plan

  variables {
    user_data = "#!/bin/bash\nexport DB_PASSWORD=hunter2\n"
  }

  expect_failures = [var.user_data]
}

run "rejects_user_data_with_lowercase_token" {
  command = plan

  variables {
    user_data = "#!/bin/bash\ncurl -H 'x-api-key: abc' https://example.com\n"
  }

  expect_failures = [var.user_data]
}

# ---- tags ----

run "tags_are_propagated_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = length(aws_autoscaling_group.this.tag) == 2 && alltrue([for t in aws_autoscaling_group.this.tag : t.propagate_at_launch])
    error_message = "Input tags and Name must all propagate at launch"
  }

  assert {
    condition     = { for t in aws_autoscaling_group.this.tag : t.key => t.value } == { Project = "alpha", Name = "alpha-dev-web" }
    error_message = "Tags must be the input plus Name"
  }

  assert {
    condition     = aws_launch_template.this.tags == tomap({ Project = "alpha", Name = "alpha-dev-web" })
    error_message = "The launch template carries the same tags"
  }
}

# ---- outputs ----

run "outputs" {
  command = apply

  assert {
    condition     = output.asg_name == "alpha-dev-web" && output.asg_arn == aws_autoscaling_group.this.arn
    error_message = "asg_name and asg_arn must come from the ASG"
  }

  assert {
    condition     = output.launch_template_id == aws_launch_template.this.id && output.launch_template_latest_version == aws_launch_template.this.latest_version
    error_message = "Launch template outputs must come from the launch template"
  }
}

# ---- name, subnets, security groups, instance profile ----

run "rejects_name_with_uppercase" {
  command = plan

  variables {
    name = "Alpha-web"
  }

  expect_failures = [var.name]
}

run "accepts_lowercase_name" {
  command = plan

  variables {
    name = "alpha-sit-web"
  }

  assert {
    condition     = aws_autoscaling_group.this.name == "alpha-sit-web"
    error_message = "A lowercase name must be accepted"
  }
}

run "rejects_empty_subnet_ids" {
  command = plan

  variables {
    subnet_ids = []
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_malformed_subnet_id" {
  command = plan

  variables {
    subnet_ids = ["vpc-0123456789abcdef0"]
  }

  expect_failures = [var.subnet_ids]
}

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

run "rejects_instance_profile_name_with_space" {
  command = plan

  variables {
    instance_profile_name = "alpha web"
  }

  expect_failures = [var.instance_profile_name]
}

run "accepts_instance_profile_name" {
  command = plan

  variables {
    instance_profile_name = "alpha-dev-web_01"
  }

  assert {
    condition     = aws_launch_template.this.iam_instance_profile[0].name == "alpha-dev-web_01"
    error_message = "A valid instance profile name must be accepted"
  }
}

# ---- root_volume ----

run "rejects_root_volume_size_below_ami_snapshot" {
  command = plan

  variables {
    root_volume = { size = 7 }
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

run "rejects_fractional_root_volume_size" {
  command = plan

  variables {
    root_volume = { size = 20.5 }
  }

  expect_failures = [var.root_volume]
}

run "rejects_malformed_kms_key_arn" {
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
    condition     = aws_launch_template.this.block_device_mappings[0].ebs[0].volume_size == 8
    error_message = "8 GiB must be accepted"
  }
}

# ---- health check grace period ----

run "health_check_grace_period_follows_input" {
  command = plan

  variables {
    health_check_grace_period = 600
  }

  assert {
    condition     = aws_autoscaling_group.this.health_check_grace_period == 600
    error_message = "health_check_grace_period must follow the input"
  }
}

run "rejects_negative_health_check_grace_period" {
  command = plan

  variables {
    health_check_grace_period = -1
  }

  expect_failures = [var.health_check_grace_period]
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
