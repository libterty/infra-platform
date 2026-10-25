resource "aws_sagemaker_pipeline" "this" {
  pipeline_name         = var.name
  pipeline_display_name = coalesce(var.display_name, var.name)
  pipeline_description  = var.description
  pipeline_definition   = var.definition
  role_arn              = var.role_arn

  dynamic "parallelism_configuration" {
    for_each = var.max_parallel_steps == null ? [] : [var.max_parallel_steps]
    content {
      max_parallel_execution_steps = parallelism_configuration.value
    }
  }

  tags = merge(var.tags, { Name = var.name })
}
