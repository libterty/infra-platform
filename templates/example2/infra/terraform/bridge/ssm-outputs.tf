# Tree B: this stack publishes under local.shared_ssm_prefix with stack = "infra".
# The module "ssm_publish" block and the published_strings / published_lists locals arrive together with the
# resources (phases B3-B5), because there is nothing to publish yet. Until then the planned keys are listed here
# in the format scripts check-ssm-contract.sh reads. Replace these lines with the real locals; do not keep both.
#
# planned_strings: alarm_topic_arn signing_private_key_secret_arn signing_public_key_secret_arn agent_runtimes
# planned_strings: ecr_repository_urls vpc_id alb_sg_id app_sg_id agent_sg_id bastion_sg_id
# planned_strings: db_proxy_endpoint db_secret_arn rate_limit_redis_endpoint stream_redis_endpoint
# planned_strings: stream_redis_id ecs_execution_role_arn api_task_role_arn worker_task_role_arn
# planned_strings: lambda_role_arn agent_runtime_role_arn
# planned_lists: services public_subnet_ids app_subnet_ids agent_subnet_ids
