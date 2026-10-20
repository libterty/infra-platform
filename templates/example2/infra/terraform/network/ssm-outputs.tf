# Keys this stack publishes under local.ssm_prefix with stack = "network".
# The module "ssm_publish" block and the published_strings / published_lists locals arrive together with the
# resources (phases B3-B5), because there is nothing to publish yet. Until then the planned keys are listed here
# in the format scripts check-ssm-contract.sh reads. Replace these lines with the real locals; do not keep both.
#
# planned_strings: vpc_id vpc_cidr alb_sg_id app_sg_id agent_sg_id db_sg_id cache_sg_id
# planned_strings: bastion_sg_id peering_connections
# planned_lists: public_subnet_ids app_subnet_ids agent_subnet_ids db_subnet_ids
