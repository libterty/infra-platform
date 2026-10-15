# Single decision point: the service list belongs to containerimage. A service configured here but not there has no
# repository, task role or security group; a service there but not configured here would never be deployed.
resource "terraform_data" "services_match_containerimage" {
  lifecycle {
    precondition {
      condition     = toset(keys(var.services)) == toset(module.in.lists["services"])
      error_message = "services must have exactly the keys of containerimage/services (${join(", ", sort(module.in.lists["services"]))})."
    }
  }
}

resource "terraform_data" "log_alarm_services_are_known" {
  lifecycle {
    precondition {
      condition     = alltrue([for s in keys(var.log_alarms) : contains(module.in.lists["services"], s)])
      error_message = "log_alarms must be keyed by services published by containerimage (${join(", ", sort(module.in.lists["services"]))})."
    }
  }
}
