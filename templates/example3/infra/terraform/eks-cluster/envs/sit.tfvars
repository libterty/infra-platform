project             = "example"
env                 = "sit"
expected_account_id = "222222222222"
deploy_role_arn     = ""

# Pick a version that is still in EKS standard support.
kubernetes_version = "1.36"

# Placeholders: replace with the roles of your people and runners (infra/README.md, execution environment).
cluster_admin_principal_arns = ["arn:aws:iam::222222222222:role/example-sit-eks-admin"]
addons_apply_principal_arn   = "arn:aws:iam::222222222222:role/example-sit-eks-addons-apply"
ci_deploy_principal_arn      = "arn:aws:iam::222222222222:role/example-sit-ci-deploy"
