# Example: a real-time endpoint on one ml.m5.large in the VPC, billed per instance hour. Use it with
# `stacks.sh dev inference plan -- -var-file=envs/examples/inference.tfvars`; the ARN is a placeholder.
project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

model_package_arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package/example-dev-models/1"
