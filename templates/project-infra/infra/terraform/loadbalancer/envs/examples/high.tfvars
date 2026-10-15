# High traffic: like standard, with a longer idle timeout for long-lived connections such as SSE.
# Copy to envs/<env>.tfvars and adjust; this file is not applied by itself.
project             = "alpha"
env                 = "prod"
expected_account_id = "222222222222"

certificate_arn     = "arn:aws:acm:ap-northeast-1:222222222222:certificate/00000000-0000-0000-0000-000000000000"
access_logs_enabled = true
idle_timeout        = 300
