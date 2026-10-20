# Keys this stack publishes under local.ssm_prefix with stack = "database".
# The module "ssm_publish" block and the published_strings / published_lists locals arrive together with the
# resources (phases B3-B5), because there is nothing to publish yet. Until then the planned keys are listed here
# in the format scripts check-ssm-contract.sh reads. Replace these lines with the real locals; do not keep both.
#
# planned_strings: db_endpoint db_reader_endpoint db_proxy_endpoint db_secret_arn
# planned_strings: rate_limit_redis_endpoint stream_redis_endpoint stream_redis_id
