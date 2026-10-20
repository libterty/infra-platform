# Keys this stack publishes under local.ssm_prefix with stack = "application".
# The module "ssm_publish" block and the published_strings / published_lists locals arrive together with the
# resources (phases B3-B5), because there is nothing to publish yet. Until then the planned keys are listed here
# in the format scripts check-ssm-contract.sh reads. Replace these lines with the real locals; do not keep both.
#
# planned_strings: cluster_name api_service_name worker_service_name api_log_group_name
# planned_strings: worker_log_group_name
