project             = "example"
env                 = "sit"
expected_account_id = "222222222222"

# No endpoint until a model version is approved (design K21): model_package_arn defaults to null and nothing is created.
# CI opens a PR that sets it after an approval; envs/examples/ shows an instance and a serverless endpoint.
