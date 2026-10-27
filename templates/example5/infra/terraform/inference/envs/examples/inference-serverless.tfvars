# Example: a serverless endpoint, billed per request; it cannot run in the VPC or capture data. Use it with
# `stacks.sh dev inference plan -- -var-file=envs/examples/inference-serverless.tfvars`; the ARN is a placeholder.
project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

model_package_arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package/example-dev-models/1"
serverless = {
  memory_size_in_mb = 2048
  max_concurrency   = 5
}
