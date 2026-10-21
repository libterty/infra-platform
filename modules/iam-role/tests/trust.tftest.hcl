mock_provider "aws" {}

variables {
  name = "alpha-dev-trust"
  trust = {
    service_principals = ["ecs-tasks.amazonaws.com"]
  }
}

run "tag_session_default_keeps_0_2_0_policy" {
  command = plan

  assert {
    condition = aws_iam_role.this.assume_role_policy == jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = ["ecs-tasks.amazonaws.com"] }
      }]
    })
    error_message = "Default trust JSON must be identical to 0.2.0"
  }
}

run "tag_session_false_explicit_same_as_default" {
  command = plan

  variables {
    trust = {
      service_principals = ["ecs-tasks.amazonaws.com"]
      tag_session        = false
    }
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Action == "sts:AssumeRole"
    error_message = "tag_session = false must keep the single sts:AssumeRole action"
  }
}

run "pod_identity_role" {
  command = plan

  variables {
    trust = {
      service_principals = ["pods.eks.amazonaws.com"]
      tag_session        = true
    }
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Action == ["sts:AssumeRole", "sts:TagSession"]
    error_message = "tag_session = true must add sts:TagSession"
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal == { Service = ["pods.eks.amazonaws.com"] }
    error_message = "Pod Identity principal must be pods.eks.amazonaws.com"
  }
}

run "tag_session_with_source_account_condition" {
  command = plan

  variables {
    trust = {
      service_principals = ["pods.eks.amazonaws.com"]
      tag_session        = true
      source_account     = "111111111111"
    }
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition == { StringEquals = { "aws:SourceAccount" = "111111111111" } }
    error_message = "Conditions must still apply with tag_session"
  }
}

run "federated_irsa_role" {
  command = plan

  variables {
    trust = {
      federated = {
        oidc_provider_arn = "arn:aws:iam::111111111111:oidc-provider/oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLE0123456789"
        subject           = "system:serviceaccount:kube-system:coredns"
      }
    }
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal == { Federated = "arn:aws:iam::111111111111:oidc-provider/oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLE0123456789" }
    error_message = "Principal must be the OIDC provider as Federated"
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
    error_message = "Action must be sts:AssumeRoleWithWebIdentity only"
  }

  assert {
    condition = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition == {
      StringEquals = {
        "oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLE0123456789:sub" = "system:serviceaccount:kube-system:coredns"
        "oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLE0123456789:aud" = "sts.amazonaws.com"
      }
    }
    error_message = "Condition must pin sub to the service account and aud to sts.amazonaws.com"
  }

  assert {
    condition     = length(jsondecode(aws_iam_role.this.assume_role_policy).Statement) == 1
    error_message = "Trust policy must have a single statement"
  }
}

run "federated_and_service_principals_rejected" {
  command = plan

  variables {
    trust = {
      service_principals = ["ecs-tasks.amazonaws.com"]
      federated = {
        oidc_provider_arn = "arn:aws:iam::111111111111:oidc-provider/oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLE0123456789"
        subject           = "system:serviceaccount:kube-system:coredns"
      }
    }
  }

  expect_failures = [var.trust]
}

run "neither_federated_nor_service_principals_rejected" {
  command = plan

  variables {
    trust = { tag_session = true }
  }

  expect_failures = [var.trust]
}

run "federated_with_source_account_rejected" {
  command = plan

  variables {
    trust = {
      source_account = "111111111111"
      federated = {
        oidc_provider_arn = "arn:aws:iam::111111111111:oidc-provider/oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLE0123456789"
        subject           = "system:serviceaccount:kube-system:coredns"
      }
    }
  }

  expect_failures = [var.trust]
}

run "federated_with_tag_session_rejected" {
  command = plan

  variables {
    trust = {
      tag_session = true
      federated = {
        oidc_provider_arn = "arn:aws:iam::111111111111:oidc-provider/oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLE0123456789"
        subject           = "system:serviceaccount:kube-system:coredns"
      }
    }
  }

  expect_failures = [var.trust]
}

run "subject_wildcard_rejected" {
  command = plan

  variables {
    trust = {
      federated = {
        oidc_provider_arn = "arn:aws:iam::111111111111:oidc-provider/oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLE0123456789"
        subject           = "system:serviceaccount:kube-system:*"
      }
    }
  }

  expect_failures = [var.trust]
}

run "subject_missing_service_account_rejected" {
  command = plan

  variables {
    trust = {
      federated = {
        oidc_provider_arn = "arn:aws:iam::111111111111:oidc-provider/oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLE0123456789"
        subject           = "system:serviceaccount:kube-system"
      }
    }
  }

  expect_failures = [var.trust]
}

run "subject_wrong_prefix_rejected" {
  command = plan

  variables {
    trust = {
      federated = {
        oidc_provider_arn = "arn:aws:iam::111111111111:oidc-provider/oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLE0123456789"
        subject           = "kube-system:coredns"
      }
    }
  }

  expect_failures = [var.trust]
}

run "oidc_provider_arn_not_a_provider_rejected" {
  command = plan

  variables {
    trust = {
      federated = {
        oidc_provider_arn = "arn:aws:iam::111111111111:role/x"
        subject           = "system:serviceaccount:kube-system:coredns"
      }
    }
  }

  expect_failures = [var.trust]
}

run "oidc_provider_arn_bad_account_rejected" {
  command = plan

  variables {
    trust = {
      federated = {
        oidc_provider_arn = "arn:aws:iam::123:oidc-provider/oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLE0123456789"
        subject           = "system:serviceaccount:kube-system:coredns"
      }
    }
  }

  expect_failures = [var.trust]
}
