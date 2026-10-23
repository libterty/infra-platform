# The repository lists belong to containerimage. A missing repository would leave an empty ARN in a policy.
resource "terraform_data" "repositories_exist" {
  lifecycle {
    precondition {
      condition     = alltrue([for r in concat(local.pod_workloads, local.runtimes) : contains(keys(local.ecr_arns), r)])
      error_message = "containerimage/ecr_repository_arns must have a repository for every EKS workload (${join(", ", local.pod_workloads)}) and every Runtime; it has: ${join(", ", sort(keys(local.ecr_arns)))}."
    }
  }
}
