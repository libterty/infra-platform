# Single decision point: network decides whether the ALB has a certificate (it narrows the ALB security group
# accordingly). If this stack disagreed, the security group would assume HTTPS while the ALB serves plain HTTP.
resource "terraform_data" "tls_matches_network" {
  lifecycle {
    precondition {
      condition     = jsondecode(module.in.strings["alb_https"]).enabled == (var.certificate_arn != null)
      error_message = "certificate_arn must be set exactly when network/alb_https is enabled (network says ${jsondecode(module.in.strings["alb_https"]).enabled})."
    }
  }
}
