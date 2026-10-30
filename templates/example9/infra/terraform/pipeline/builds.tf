# The five CodeBuild projects the pipelines run (design 8.2, K3, K5, K9). The buildspecs live in the application repo;
# the template only names their paths. Every project runs with its own role from the iam stack.
locals {
  # Must match build_project_names in iam/naming.tf: each role trusts, and the pipeline role starts, only these names.
  build_project_names = {
    api_build      = "${local.name_prefix}-api-build"
    api_deploy     = "${local.name_prefix}-api-deploy"
    fn_build       = "${local.name_prefix}-fn-build"
    web_build      = "${local.name_prefix}-web-build"
    web_invalidate = "${local.name_prefix}-web-invalidate"
  }

  build_project_settings = {
    api_build = {
      description = "建 api 映像檔並推到 ECR，輸出 IMAGE_URI"
      privileged  = true
      variables   = { REPOSITORY_URI = module.in.strings["api_repository_url"] }
    }
    # Design 5.4: copy the latest revision of the family, swap the image, register it and update the service.
    api_deploy = {
      description = "用 Build 輸出的映像檔註冊 api 新的 task definition 版本並更新 service"
      privileged  = false
      variables = {
        CLUSTER_NAME = module.in.strings["cluster_name"]
        SERVICE_NAME = module.in.strings["api_service_name"]
        TASK_FAMILY  = module.in.strings["api_task_family"]
        # ecs-service always names the container app.
        CONTAINER_NAME = "app"
      }
    }
    fn_build = {
      description = "建 fn 映像檔、推到 ECR、更新函式並發布版本，輸出 VERSION"
      privileged  = true
      variables = {
        REPOSITORY_URI = module.in.strings["fn_repository_url"]
        FUNCTION_NAME  = module.in.strings["fn_function_name"]
      }
    }
    web_build = {
      description = "建前端靜態檔，輸出給 S3 部署 action"
      privileged  = false
      variables   = {}
    }
    web_invalidate = {
      description = "部署前端之後清除 CloudFront 快取"
      privileged  = false
      variables   = { DISTRIBUTION_ID = module.in.strings["distribution_id"] }
    }
  }

  # Everything module.build receives, so the tests can check it per project.
  build_projects = {
    for k, p in local.build_project_settings : k => {
      name             = local.build_project_names[k]
      description      = p.description
      service_role_arn = module.in.strings["${k}_role_arn"]
      buildspec        = "buildspec/${replace(k, "_", "-")}.yml"
      privileged       = p.privileged
      # Docker layer cache only where docker runs; the source comes from the pipeline, so a source cache would not help.
      cache_modes           = p.privileged ? ["LOCAL_DOCKER_LAYER_CACHE"] : []
      environment_variables = { for name, value in p.variables : name => { value = value, type = "PLAINTEXT" } }
    }
  }
}

module "build" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/codebuild-project/aws"
  version  = "~> 0.1.0"
  for_each = local.build_projects

  name                  = each.value.name
  description           = each.value.description
  service_role_arn      = each.value.service_role_arn
  buildspec             = each.value.buildspec
  environment           = { privileged_mode = each.value.privileged }
  cache_modes           = each.value.cache_modes
  environment_variables = each.value.environment_variables
  encryption_key_arn    = module.in.strings["kms_key_arn"]
  log_retention_days    = var.log_retention_days
  log_kms_key_arn       = module.in.strings["kms_key_arn"]
}
