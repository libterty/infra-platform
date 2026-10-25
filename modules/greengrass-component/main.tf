locals {
  recipe = var.recipe != null ? var.recipe : try(jsondecode(var.recipe_json), null)

  component_name    = try(tostring(local.recipe.ComponentName), "")
  component_version = try(tostring(local.recipe.ComponentVersion), "")

  artifact_uris = flatten([
    for m in try(local.recipe.Manifests, []) : [for a in try(m.Artifacts, []) : try(tostring(a.Uri), "")]
  ])
}

resource "awscc_greengrassv2_component_version" "this" {
  # Re-encoding a JSON recipe makes whitespace-only edits of the file a no-op instead of a replacement.
  inline_recipe = jsonencode(local.recipe)

  tags = merge(var.tags, { Name = local.component_name })

  lifecycle {
    precondition {
      condition     = local.recipe == null || can(regex("^[A-Za-z0-9._-]{1,128}$", local.component_name))
      error_message = "The recipe must set ComponentName to 1-128 chars of letters, digits, dots, underscores and hyphens."
    }

    precondition {
      condition     = local.recipe == null || !startswith(local.component_name, "aws.greengrass.")
      error_message = "ComponentName must not start with aws.greengrass., which is reserved for AWS-provided components."
    }

    precondition {
      condition     = local.recipe == null || can(regex("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$", local.component_version))
      error_message = "The recipe must set ComponentVersion to a semantic version (major.minor.patch)."
    }

    precondition {
      condition     = local.recipe == null || try(local.recipe.RecipeFormatVersion, "") == "2020-01-25"
      error_message = "The recipe must set RecipeFormatVersion to 2020-01-25."
    }

    precondition {
      condition     = local.recipe == null || contains(["aws.greengrass.generic"], try(local.recipe.ComponentType, "aws.greengrass.generic"))
      error_message = "Only generic components are supported; Lambda, plugin and nucleus component types are rejected."
    }

    precondition {
      condition     = alltrue([for u in local.artifact_uris : startswith(u, "s3://${var.artifact_bucket_name}/")])
      error_message = "Every artifact Uri in the recipe must start with s3://<artifact_bucket_name>/."
    }
  }
}
