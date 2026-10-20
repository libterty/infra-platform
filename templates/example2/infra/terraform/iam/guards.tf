# The repository lists belong to containerimage. A missing repository would leave an empty ARN in a policy.
resource "terraform_data" "repositories_exist" {
  lifecycle {
    precondition {
      condition     = alltrue([for r in concat(local.ecs_services, local.runtimes) : contains(keys(local.ecr_arns), r)])
      error_message = "containerimage/ecr_repository_arns must have a repository for every ECS service (${join(", ", local.ecs_services)}) and every Runtime; it has: ${join(", ", sort(keys(local.ecr_arns)))}."
    }
  }
}
