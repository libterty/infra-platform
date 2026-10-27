project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

# No endpoint until a model version is approved (design K21): model_package_arn defaults to null and nothing is created.
# CI opens a PR that sets it after an approval; envs/examples/ shows an instance and a serverless endpoint.
