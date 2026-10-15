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

# Tracing needs a collector image, and a task with no NAT needs a private way to reach the image and X-Ray.
resource "terraform_data" "tracing_has_collector_image" {
  lifecycle {
    precondition {
      condition     = !local.tracing_on || var.adot_collector != null
      error_message = "iam-app traces ${join(", ", sort(tolist(local.tracing)))}; set adot_collector (an explicit tag and source) in this stack."
    }
  }
}

resource "terraform_data" "adot_mirror_is_published" {
  lifecycle {
    precondition {
      condition     = !local.collector_mirror || contains(jsondecode(module.in_tracing.strings["mirrored_images"]), local.adot_mirror_name)
      error_message = "adot_collector.source is mirror, so containerimage must list ${local.adot_mirror_name} in mirrored_images and the image must be copied into that repository."
    }
  }
}

# nat_mode external is a customer-managed VPC: its NAT is the customer's to provide, so it is not checked here.
resource "terraform_data" "no_nat_collector_from_mirror" {
  lifecycle {
    precondition {
      condition     = local.nat_mode != "none" || local.collector_source == "mirror"
      error_message = "network has no NAT (nat mode none), so the collector image cannot be pulled from ECR Public. Mirror it into containerimage (mirrored_images) and set adot_collector.source to mirror."
    }
  }
}

locals {
  # The mirror image is pulled from private ECR (ecr.api and ecr.dkr; its layers come from S3, which needs a gateway endpoint) and traces go to xray.
  required_endpoints = toset(["xray", "ecr.api", "ecr.dkr"])
  missing_endpoints  = local.nat_mode == "none" ? setsubtract(local.required_endpoints, local.interface_endpoints) : toset([])
}

resource "terraform_data" "no_nat_endpoints_exist" {
  lifecycle {
    precondition {
      condition     = length(local.missing_endpoints) == 0
      error_message = "network has no NAT (nat mode none), so it needs these interface endpoints for tracing: ${join(", ", sort(tolist(local.missing_endpoints)))}. Add them to interface_endpoints.services in network. The VPC also needs an S3 gateway endpoint (not checked here)."
    }
  }
}
