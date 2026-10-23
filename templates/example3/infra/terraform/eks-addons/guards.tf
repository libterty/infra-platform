locals {
  # Contract versions of eks-cluster this stack understands.
  supported_eks_contract_versions = ["1"]
}

resource "terraform_data" "eks_contract_version" {
  lifecycle {
    precondition {
      condition     = contains(local.supported_eks_contract_versions, module.in.strings["contract_version"])
      error_message = "eks-cluster/contract_version is ${module.in.strings["contract_version"]}; this stack understands ${join(", ", local.supported_eks_contract_versions)}."
    }
  }
}
