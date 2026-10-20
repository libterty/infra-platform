project             = "example"
env                 = "dev"
expected_account_id = "111111111111"
deploy_role_arn     = ""

# Terraform owns the image tags: build and push the images, then change these and apply.
import_extract_image_tag = "0.1.0"
import_load_image_tag    = "0.1.0"

# The bastion belongs to this stack but its network paths belong to the network stack; the two must agree, and
# check-ssm-contract.sh fails when they do not.
bastion_enabled = true
