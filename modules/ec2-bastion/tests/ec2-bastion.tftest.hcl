mock_provider "aws" {
  override_data {
    target = data.aws_ami.al2023
    values = {
      id = "ami-0123456789abcdef0"
    }
  }
}

variables {
  name                  = "alpha-dev-bastion"
  subnet_id             = "subnet-0123456789abcdef0"
  security_group_ids    = ["sg-0123456789abcdef0"]
  instance_profile_name = "alpha-dev-bastion"
}

run "defaults" {
  command = plan

  assert {
    condition = (
      aws_instance.this.subnet_id == "subnet-0123456789abcdef0" &&
      aws_instance.this.vpc_security_group_ids == toset(["sg-0123456789abcdef0"]) &&
      aws_instance.this.iam_instance_profile == "alpha-dev-bastion"
    )
    error_message = "Subnet, security groups and instance profile must follow the input"
  }

  assert {
    condition     = aws_instance.this.instance_type == "t4g.nano"
    error_message = "Default instance_type must be t4g.nano"
  }

  assert {
    condition     = aws_instance.this.ami == "ami-0123456789abcdef0"
    error_message = "The instance must use the AMI found by the data source"
  }

  assert {
    condition     = aws_instance.this.tags == tomap({ Name = "alpha-dev-bastion" })
    error_message = "Without tags input the only tag is Name"
  }
}

# ---- AMI lookup ----

run "ami_is_amazon_linux_2023_arm64_by_default" {
  command = plan

  assert {
    condition     = toset(data.aws_ami.al2023.owners) == toset(["amazon"])
    error_message = "The AMI must come from the amazon owner"
  }

  assert {
    condition     = data.aws_ami.al2023.most_recent == true
    error_message = "The AMI lookup must pick the most recent image"
  }

  assert {
    condition     = contains(flatten([for f in data.aws_ami.al2023.filter : tolist(f.values) if f.name == "name"]), "al2023-ami-2023.*-kernel-*-arm64")
    error_message = "The AMI name filter must select Amazon Linux 2023 for arm64"
  }

  assert {
    condition     = contains(flatten([for f in data.aws_ami.al2023.filter : tolist(f.values) if f.name == "architecture"]), "arm64")
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
    condition     = contains(flatten([for f in data.aws_ami.al2023.filter : tolist(f.values) if f.name == "name"]), "al2023-ami-2023.*-kernel-*-x86_64")
    error_message = "The AMI name filter must select Amazon Linux 2023 for x86_64"
  }

  assert {
    condition     = contains(flatten([for f in data.aws_ami.al2023.filter : tolist(f.values) if f.name == "architecture"]), "x86_64")
    error_message = "The AMI architecture filter must be x86_64"
  }
}

# ---- security: IMDSv2, no public IP, encryption ----

run "imdsv2_is_required" {
  command = plan

  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required (http_tokens = required)"
  }

  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens != "optional"
    error_message = "IMDSv1 must not be allowed"
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
    error_message = "The metadata hop limit must be 1 so containers on the host cannot reach IMDS"
  }
}

run "no_public_ip" {
  command = plan

  assert {
    condition     = aws_instance.this.associate_public_ip_address == false
    error_message = "associate_public_ip_address must be false, not null: a public subnet default must not apply"
  }
}

run "root_volume_is_encrypted_gp3" {
  command = plan

  assert {
    condition     = aws_instance.this.root_block_device[0].encrypted == true
    error_message = "The root volume must be encrypted"
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].volume_type == "gp3"
    error_message = "The root volume must be gp3"
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].volume_size == 8
    error_message = "Default root_volume_size must be 8"
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].delete_on_termination == true
    error_message = "The root volume must be deleted with the instance"
  }
}

run "root_volume_size_follows_input" {
  command = plan

  variables {
    root_volume_size = 30
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].volume_size == 30
    error_message = "root_volume_size must follow the input"
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].encrypted == true
    error_message = "The root volume must stay encrypted when the size changes"
  }
}

run "tags_are_merged_with_name_on_instance_and_root_volume" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_instance.this.tags == tomap({ Project = "alpha", Name = "alpha-dev-bastion" })
    error_message = "Input tags must be kept and Name added on the instance"
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].tags == tomap({ Project = "alpha", Name = "alpha-dev-bastion" })
    error_message = "The root volume must carry the same tags"
  }
}

run "outputs" {
  command = apply

  assert {
    condition     = output.instance_id == aws_instance.this.id
    error_message = "instance_id must be the instance id"
  }

  assert {
    condition     = output.private_ip == aws_instance.this.private_ip
    error_message = "private_ip must be the instance private IP"
  }

  assert {
    condition     = output.ami_id == "ami-0123456789abcdef0"
    error_message = "ami_id must be the AMI id found by the data source"
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
    architecture  = "arm64"
  }

  expect_failures = [var.instance_type]
}

run "rejects_x86_64_with_graviton_instance_type" {
  command = plan

  variables {
    architecture = "x86_64"
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
    instance_type = "m7g.large"
  }

  assert {
    condition     = aws_instance.this.instance_type == "m7g.large"
    error_message = "A Graviton instance type with arm64 must be accepted"
  }
}

run "accepts_arm64_with_graviton_instance_type_with_suffix" {
  command = plan

  variables {
    instance_type = "c6gn.medium"
  }

  assert {
    condition     = aws_instance.this.instance_type == "c6gn.medium"
    error_message = "A Graviton family with a suffix such as c6gn must be accepted with arm64"
  }
}

# g4dn and m7i-flex are x86 families whose names contain the letter g or look unusual; they must not be taken for Graviton.
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

run "accepts_x86_64_with_flex_instance_type" {
  command = plan

  variables {
    instance_type = "m7i-flex.large"
    architecture  = "x86_64"
  }

  assert {
    condition     = aws_instance.this.instance_type == "m7i-flex.large"
    error_message = "m7i-flex is x86 and must be accepted with x86_64"
  }
}

run "rejects_instance_type_without_size" {
  command = plan

  variables {
    instance_type = "nano"
  }

  expect_failures = [var.instance_type]
}

# ---- root_volume_size ----

run "rejects_root_volume_size_below_ami_snapshot" {
  command = plan

  variables {
    root_volume_size = 7
  }

  expect_failures = [var.root_volume_size]
}

run "rejects_fractional_root_volume_size" {
  command = plan

  variables {
    root_volume_size = 8.5
  }

  expect_failures = [var.root_volume_size]
}

run "rejects_root_volume_size_above_gp3_limit" {
  command = plan

  variables {
    root_volume_size = 16385
  }

  expect_failures = [var.root_volume_size]
}

run "accepts_root_volume_size_8" {
  command = plan

  variables {
    root_volume_size = 8
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].volume_size == 8
    error_message = "8 GiB must be accepted"
  }
}

# ---- name, subnet, instance profile ----

run "rejects_name_with_uppercase" {
  command = plan

  variables {
    name = "Alpha-bastion"
  }

  expect_failures = [var.name]
}

run "rejects_name_with_underscore" {
  command = plan

  variables {
    name = "alpha_dev_bastion"
  }

  expect_failures = [var.name]
}

run "accepts_lowercase_name" {
  command = plan

  variables {
    name = "alpha-sit-bastion"
  }

  assert {
    condition     = aws_instance.this.tags["Name"] == "alpha-sit-bastion"
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

run "rejects_empty_instance_profile_name" {
  command = plan

  variables {
    instance_profile_name = ""
  }

  expect_failures = [var.instance_profile_name]
}

run "rejects_instance_profile_name_with_space" {
  command = plan

  variables {
    instance_profile_name = "alpha bastion"
  }

  expect_failures = [var.instance_profile_name]
}

run "accepts_instance_profile_name" {
  command = plan

  variables {
    instance_profile_name = "alpha-dev-bastion_01"
  }

  assert {
    condition     = aws_instance.this.iam_instance_profile == "alpha-dev-bastion_01"
    error_message = "A valid instance profile name must be accepted"
  }
}
