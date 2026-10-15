# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/0000" }
}

run "tfvars_create_one_repository_per_service" {
  command = plan

  assert {
    condition     = length(var.services) > 0 && length(module.ecr) == length(var.services)
    error_message = "tfvars must list at least one service and every service must get a repository"
  }

  assert {
    condition     = local.published_lists == { services = var.services }
    error_message = "The service list in tfvars must be published as it is"
  }
}

run "tfvars_create_one_repository_per_mirror" {
  command = plan

  assert {
    condition     = length(module.ecr_mirror) == length(var.mirrored_images)
    error_message = "Every entry of mirrored_images in tfvars must get a repository"
  }

  assert {
    condition     = length(jsondecode(local.published_strings["mirrored_images"])) == length(var.mirrored_images) && alltrue([for m in jsondecode(local.published_strings["mirrored_images"]) : contains(var.mirrored_images, m)])
    error_message = "The mirror list in tfvars must be published as it is"
  }
}
