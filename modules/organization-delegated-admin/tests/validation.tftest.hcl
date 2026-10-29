mock_provider "aws" {}

variables {
  delegated_admin_account_id = "333333333333"
  services                   = ["guardduty"]
}

run "account_id_of_11_digits_is_rejected" {
  command = plan

  variables {
    delegated_admin_account_id = "33333333333"
  }

  expect_failures = [var.delegated_admin_account_id]
}

run "account_id_with_letters_is_rejected" {
  command = plan

  variables {
    delegated_admin_account_id = "33333333333a"
  }

  expect_failures = [var.delegated_admin_account_id]
}

run "unknown_service_is_rejected" {
  command = plan

  variables {
    services = ["guardduty", "macie"]
  }

  expect_failures = [var.services]
}

run "backup_is_rejected" {
  command = plan

  variables {
    services = ["backup"]
  }

  expect_failures = [var.services]
}

run "empty_services_is_rejected" {
  command = plan

  variables {
    services = []
  }

  expect_failures = [var.services]
}

run "malformed_region_is_rejected" {
  command = plan

  variables {
    regions = ["tokyo"]
  }

  expect_failures = [var.regions]
}
