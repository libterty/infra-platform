# The service list is published by containerimage; a missing entry means no repository for that image.
resource "terraform_data" "services_present" {
  lifecycle {
    precondition {
      condition     = alltrue([for s in keys(local.service_names) : contains(module.shared.lists["services"], s)])
      error_message = "The service list in tree B (services) must contain api and worker; containerimage must create their repositories."
    }
  }
}
