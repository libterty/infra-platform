# Single decision point: the service list belongs to containerimage. A service missing here would get no security group.
resource "terraform_data" "services_match_containerimage" {
  lifecycle {
    precondition {
      condition     = toset(keys(var.services)) == toset(module.in.lists["services"])
      error_message = "services must have exactly the keys of containerimage/services (${join(", ", sort(module.in.lists["services"]))})."
    }
  }
}

# Single decision point: the Runtime list belongs to containerimage. A Runtime missing here would get no security group.
resource "terraform_data" "agent_runtimes_match_containerimage" {
  lifecycle {
    precondition {
      condition     = jsonencode(keys(var.agent_runtimes)) == jsonencode(sort(jsondecode(module.in.strings["agent_runtimes"])))
      error_message = "agent_runtimes must have exactly the keys of containerimage/agent_runtimes (${join(", ", jsondecode(module.in.strings["agent_runtimes"]))})."
    }
  }
}
