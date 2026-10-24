# Switching warehouse_mode replaces this resource, and prevent_destroy rejects the plan.
# See the README runbook before changing it; never commit prevent_destroy = false.
resource "terraform_data" "warehouse_mode_guard" {
  triggers_replace = var.warehouse_mode

  lifecycle {
    prevent_destroy = true
  }
}
