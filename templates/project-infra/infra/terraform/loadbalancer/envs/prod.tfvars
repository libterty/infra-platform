project             = "alpha"
env                 = "prod"
expected_account_id = "222222222222"

# Replace with the ACM certificate of the production domain. Must agree with network/alb_https (true in prod).
certificate_arn     = "arn:aws:acm:ap-northeast-1:222222222222:certificate/00000000-0000-0000-0000-000000000000"
access_logs_enabled = true
