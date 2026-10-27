project             = "example"
env                 = "sit"
expected_account_id = "222222222222"

# Account-level IoT settings (fleet indexing, logging, registry events): only ONE project per account and region may set
# them. A second project in the same account must set null.
account_settings = {
  log_level = "WARN"
}

# Account-level Device Defender audit configuration: same rule, a second project in the same account sets null. The
# weekly scheduled audit and the quarantine mitigation action of this project are created either way.
device_defender_audit = {}

# Placeholder: the code signing certificate imported into ACM outside Terraform (design K17). Replace it.
ota_signing_certificate_arn = "arn:aws:acm:ap-northeast-1:222222222222:certificate/00000000-0000-0000-0000-000000000000"

# OTA jobs: devices notified per minute, and the failure percentage that cancels the job (design section 7.5).
ota_rollout = {
  maximum_per_minute         = 20
  abort_threshold_percentage = 5
}
