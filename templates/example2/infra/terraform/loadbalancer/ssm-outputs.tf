# Keys this stack publishes under local.ssm_prefix with stack = "loadbalancer".
# The module "ssm_publish" block and the published_strings / published_lists locals arrive together with the
# resources (phases B3-B5), because there is nothing to publish yet. Until then the planned keys are listed here
# in the format scripts check-ssm-contract.sh reads. Replace these lines with the real locals; do not keep both.
#
# planned_strings: alb_arn_suffix target_group_arn_suffixes waf_web_acl_name api_target_group_arn
