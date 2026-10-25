project             = "example"
env                 = "sit"
expected_account_id = "222222222222"

# No cameras (design section 7.5): nothing is created. To add one, give the same entry here and in edge/envs/sit.tfvars:
# cameras = {
#   gate = {
#     core_thing_name = "example-sit-core-001"
#     rtsp_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:222222222222:secret:example-sit/cam-gate"
#     retention_hours = 24
#   }
# }
cameras = {}

# SiteWise gateways on Greengrass core devices, gateway name -> { core_device_thing_name }.
gateways = {}
