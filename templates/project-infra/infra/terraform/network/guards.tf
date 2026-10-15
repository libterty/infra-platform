# Single decision point: the service list belongs to containerimage. A service missing here would get no security group.
resource "terraform_data" "services_match_containerimage" {
  lifecycle {
    precondition {
      condition     = toset(keys(var.services)) == toset(module.in.lists["services"])
      error_message = "services must have exactly the keys of containerimage/services (${join(", ", sort(module.in.lists["services"]))})."
    }
  }
}
