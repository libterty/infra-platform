# iam-app decides which services are traced (it also gives those task roles their X-Ray permissions); this stack only
# follows that list. Everything below is inert while the list is empty.
locals {
  # Name of the repository in containerimage's mirrored_images that holds the collector image.
  adot_mirror_name = "adot-collector"

  tracing    = toset(jsondecode(module.in.strings["tracing"]))
  tracing_on = length(local.tracing) > 0

  collector_source = try(var.adot_collector.source, null)
  collector_mirror = local.tracing_on && local.collector_source == "mirror"

  # Only read when something is traced, so a project that never traces needs none of these keys.
  ssm_tracing_strings = merge(
    local.tracing_on ? {
      nat                 = "network/nat"
      interface_endpoints = "network/interface_endpoints"
    } : {},
    local.collector_mirror ? {
      mirrored_images = "containerimage/mirrored_images"
      mirror_url      = "containerimage/ecr_mirror_${replace(local.adot_mirror_name, "-", "_")}_url"
    } : {},
  )
}

module "in_tracing" {
  source = "../../../../../modules/ssm-read" # After copying out of this repo, change to app.terraform.io/<org>/ssm-read/aws

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_tracing_strings
}

locals {
  nat_mode            = local.tracing_on ? jsondecode(module.in_tracing.strings["nat"]).mode : null
  interface_endpoints = local.tracing_on ? toset(jsondecode(module.in_tracing.strings["interface_endpoints"])) : toset([])

  # null while nothing is traced or no collector is configured; guards.tf reports the second case.
  collector_image = !local.tracing_on || var.adot_collector == null ? null : (
    local.collector_mirror
    ? "${module.in_tracing.strings["mirror_url"]}:${var.adot_collector.tag}"
    : "public.ecr.aws/aws-observability/aws-otel-collector:${var.adot_collector.tag}"
  )

  # Same fields as modules/ecs-service/examples/adot-sidecar. essential = false: a collector failure must not stop the task.
  collector_sidecars = local.collector_image == null ? [] : [{
    name               = "adot-collector"
    image              = local.collector_image
    essential          = false
    cpu                = 128
    memory_reservation = 256
    environment        = { AOT_CONFIG_CONTENT = file("${path.module}/adot-collector.yaml") }
    port_mappings      = [{ container_port = 4317 }]
    health_check       = { command = ["CMD", "/healthcheck"] }
    app_depends_on     = "START"
  }]

  # Containers share the task network interface, so localhost reaches the collector. The service name is the one the
  # xray_sampling_rules use.
  tracing_environment = {
    for s in keys(var.services) : s => contains(local.tracing, s) ? {
      OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4317"
      OTEL_SERVICE_NAME           = "${local.name_prefix}-${s}"
    } : {}
  }

  tracing_sidecars = { for s in keys(var.services) : s => contains(local.tracing, s) ? local.collector_sidecars : [] }
}
