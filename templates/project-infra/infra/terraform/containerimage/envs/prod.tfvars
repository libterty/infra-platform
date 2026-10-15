project             = "alpha"
env                 = "prod"
expected_account_id = "222222222222"

services = ["api", "worker"]

# Copies of external images for environments without internet access, for example ["adot-collector"].
mirrored_images = []
