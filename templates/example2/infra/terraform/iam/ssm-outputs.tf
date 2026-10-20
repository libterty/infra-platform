# Keys this stack publishes under local.ssm_prefix with stack = "iam".
# The module "ssm_publish" block and the published_strings / published_lists locals arrive together with the
# resources (phases B3-B5), because there is nothing to publish yet. Until then the planned keys are listed here
# in the format scripts check-ssm-contract.sh reads. Replace these lines with the real locals; do not keep both.
#
# planned_strings: ecs_execution_role_arn api_task_role_arn worker_task_role_arn lambda_role_arn
# planned_strings: agent_runtime_role_arn
