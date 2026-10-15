# PoC: fixed task counts, trace everything, no log alarms. Copy to envs/<env>.tfvars and adjust; not applied by itself.
# Sampling rules only apply to SDKs or collectors that use X-Ray remote sampling.
project             = "alpha"
env                 = "dev"
expected_account_id = "111111111111"

services = {
  api = {
    image_tag      = "0000000"
    container_port = 8080
    desired_count  = 1
    alb = {
      priority      = 100
      path_patterns = ["/api/*"]
    }
  }
  worker = {
    image_tag      = "0000000"
    container_port = 9000
    desired_count  = 1
  }
}

xray_sampling_rules = {
  all = { priority = 100, fixed_rate = 1, reservoir_size = 1 }
}
