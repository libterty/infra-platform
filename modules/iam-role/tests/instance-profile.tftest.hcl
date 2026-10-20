mock_provider "aws" {}

variables {
  name = "alpha-dev-bastion"
  trust = {
    service_principals = ["ec2.amazonaws.com"]
  }
}

run "default_creates_no_instance_profile" {
  command = plan

  assert {
    condition     = length(aws_iam_instance_profile.this) == 0
    error_message = "No instance profile may be created when instance_profile_name is null"
  }

  assert {
    condition     = output.instance_profile_name == null && output.instance_profile_arn == null
    error_message = "Instance profile outputs must be null when none is created"
  }
}

run "name_creates_instance_profile_bound_to_role" {
  command = apply

  variables {
    instance_profile_name = "alpha-dev-bastion"
  }

  assert {
    condition     = length(aws_iam_instance_profile.this) == 1
    error_message = "Exactly one instance profile must be created"
  }

  assert {
    condition     = aws_iam_instance_profile.this[0].name == "alpha-dev-bastion"
    error_message = "Instance profile must use the given name"
  }

  assert {
    condition     = aws_iam_instance_profile.this[0].role == aws_iam_role.this.name
    error_message = "Instance profile must be bound to this role"
  }

  assert {
    condition     = aws_iam_instance_profile.this[0].tags["Name"] == "alpha-dev-bastion"
    error_message = "Instance profile must carry the Name tag"
  }

  assert {
    condition     = output.instance_profile_name == "alpha-dev-bastion"
    error_message = "instance_profile_name output must return the profile name"
  }

  assert {
    condition     = output.instance_profile_arn != null
    error_message = "instance_profile_arn output must be set when a profile is created"
  }
}

run "name_with_allowed_special_characters_accepted" {
  command = plan

  variables {
    instance_profile_name = "alpha+dev=bastion,1.0@example-x_y"
  }

  assert {
    condition     = length(aws_iam_instance_profile.this) == 1
    error_message = "Allowed special characters must be accepted"
  }
}

run "name_at_128_chars_accepted" {
  command = plan

  variables {
    instance_profile_name = replace(format("%128s", "x"), " ", "a")
  }

  assert {
    condition     = length(aws_iam_instance_profile.this) == 1
    error_message = "A 128 character name must be accepted"
  }
}

run "name_at_129_chars_rejected" {
  command = plan

  variables {
    instance_profile_name = replace(format("%129s", "x"), " ", "a")
  }

  expect_failures = [var.instance_profile_name]
}

run "name_with_space_rejected" {
  command = plan

  variables {
    instance_profile_name = "alpha dev"
  }

  expect_failures = [var.instance_profile_name]
}

run "empty_name_rejected" {
  command = plan

  variables {
    instance_profile_name = ""
  }

  expect_failures = [var.instance_profile_name]
}
