# ECS Exec is switched on per service here and published to application; a name that is not a service would silently do nothing.
resource "terraform_data" "ecs_exec_services_are_known" {
  lifecycle {
    precondition {
      condition     = alltrue([for s in var.ecs_exec_services : contains(module.in.lists["services"], s)])
      error_message = "ecs_exec_services must name services published by containerimage (${join(", ", module.in.lists["services"])})."
    }
  }
}

# Tracing is switched on per service here and published to application; a name that is not a service would silently do nothing.
resource "terraform_data" "tracing_services_are_known" {
  lifecycle {
    precondition {
      condition     = alltrue([for s in var.tracing : contains(module.in.lists["services"], s)])
      error_message = "tracing must name services published by containerimage (${join(", ", module.in.lists["services"])})."
    }
  }
}
