locals {
  # These two hold JSON in a String (SSM has no map type); the late stacks jsondecode them.
  json_array_keys  = ["agent_runtimes"]
  json_object_keys = ["ecr_repository_urls"]

  # A certificate only serves resources in its own region: the ALB's region, and us-east-1 for CloudFront.
  certificate_regions = {
    alb_certificate_arn        = var.aws_region
    cloudfront_certificate_arn = "us-east-1"
  }

  empty_string_keys = [for k, v in local.published_strings : k if trimspace(v) == ""]
  short_subnet_keys = [for k, v in local.published_lists : k if endswith(k, "_subnet_ids") && length(v) < 2]
  bad_json_keys = concat(
    [for k in local.json_array_keys : k if !can(tolist(jsondecode(local.published_strings[k])))],
    [for k in local.json_object_keys : k if !can(keys(jsondecode(local.published_strings[k])))],
  )
  wrong_region_certificate_keys = [
    for k, r in local.certificate_regions : k
    if !can(regex("^arn:aws[a-z-]*:acm:${r}:[0-9]{12}:certificate/", local.published_strings[k]))
  ]
}

# SSM rejects an empty String, so catch it here with the key name instead of a late provider error.
resource "terraform_data" "values_not_empty" {
  lifecycle {
    precondition {
      condition     = length(local.empty_string_keys) == 0
      error_message = "Tree A values must not be empty: ${join(", ", local.empty_string_keys)}. Apply the stack that publishes them first."
    }
  }
}

# Every subnet tier spans two AZs; a single subnet means the stack that publishes it ran with one AZ.
resource "terraform_data" "subnets_span_two_azs" {
  lifecycle {
    precondition {
      condition     = length(local.short_subnet_keys) == 0
      error_message = "Subnet lists need at least 2 subnets: ${join(", ", local.short_subnet_keys)}."
    }
  }
}

resource "terraform_data" "json_values_decode" {
  lifecycle {
    precondition {
      condition     = length(local.bad_json_keys) == 0
      error_message = "These values must be JSON (agent_runtimes an array, ecr_repository_urls an object): ${join(", ", local.bad_json_keys)}."
    }
  }
}

resource "terraform_data" "certificates_in_their_regions" {
  lifecycle {
    precondition {
      condition     = length(local.wrong_region_certificate_keys) == 0
      error_message = "These must be ACM certificate ARNs in their region (alb_certificate_arn in aws_region, cloudfront_certificate_arn in us-east-1): ${join(", ", local.wrong_region_certificate_keys)}."
    }
  }
}
