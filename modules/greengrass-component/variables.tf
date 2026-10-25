variable "recipe" {
  type        = any
  default     = null
  description = "元件的 recipe，用 HCL 物件寫（欄位名稱照 Greengrass recipe 的 JSON 格式，例如 `ComponentName`、`ComponentVersion`、`Manifests`），module 會 `jsonencode`。跟 `recipe_json` 擇一。`RecipeFormatVersion` 必須是 `2020-01-25`，`ComponentVersion` 是 semver，所有 artifact 的 `Uri` 都要在 `artifact_bucket_name` 裡。"
}

variable "recipe_json" {
  type        = string
  default     = null
  description = "元件的 recipe，JSON 字串（例如 `file(\"components/com.example.Inference/1.0.0.json\")`）。跟 `recipe` 擇一，規則相同；不收 YAML。"

  validation {
    condition     = (var.recipe == null) != (var.recipe_json == null)
    error_message = "Exactly one of recipe and recipe_json must be set."
  }

  validation {
    condition     = var.recipe_json == null || can(keys(jsondecode(var.recipe_json)))
    error_message = "recipe_json must be a JSON object."
  }
}

variable "artifact_bucket_name" {
  type        = string
  description = "放 artifact 的 S3 bucket 名稱（不含 `s3://`）。recipe 裡每個 artifact 的 `Uri` 都必須以 `s3://<artifact_bucket_name>/` 開頭；core device 的 token exchange role 要能 `s3:GetObject` 這個 bucket。"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.artifact_bucket_name))
    error_message = "artifact_bucket_name must be an S3 bucket name (3-63 chars of lowercase letters, digits, dots and hyphens), without the s3:// prefix."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "元件版本的 tag；`Name`（元件名稱）由 module 加上。"
}
