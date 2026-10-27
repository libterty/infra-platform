locals {
  # One recipe file per component version, templates/example5/edge/components/<component>/<version>.json (design K10).
  # A version is immutable: change a recipe by adding a new file. ${artifact_bucket} in a recipe is replaced with the
  # greengrass-artifacts bucket of storage, where CI uploads artifacts/<component>/<version>/.
  components_dir = "${path.module}/../../../edge/components"
  recipes = {
    for f in fileset(local.components_dir, "*/*.json") : trimsuffix(f, ".json") => templatefile("${local.components_dir}/${f}", {
      artifact_bucket = module.in.strings["greengrass_artifacts_bucket_name"]
    })
  }
}

module "component" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/greengrass-component/aws"
  version  = "~> 0.1.0"
  for_each = local.recipes

  recipe_json          = each.value
  artifact_bucket_name = module.in.strings["greengrass_artifacts_bucket_name"]
  tags                 = local.awscc_tags
}
