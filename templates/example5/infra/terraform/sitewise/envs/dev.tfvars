project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

# No cameras (design section 7.5): nothing is created. To add one, give the same entry here and in edge/envs/dev.tfvars:
# cameras = {
#   gate = {
#     core_thing_name = "example-dev-core-001"
#     rtsp_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/cam-gate"
#     retention_hours = 24
#   }
# }
cameras = {}

# SiteWise gateways on Greengrass core devices, gateway name -> { core_device_thing_name }.
gateways = {}
