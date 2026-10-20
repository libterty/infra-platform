# Keys this stack publishes under local.ssm_prefix with stack = "agent".
# The module "ssm_publish" block and the published_strings / published_lists locals arrive together with the
# resources (phases B3-B5), because there is nothing to publish yet. Until then the planned keys are listed here
# in the format scripts check-ssm-contract.sh reads. Replace these lines with the real locals; do not keep both.
#
# planned_strings: agent_runtime_arns agent_memory_id guardrail_ids
