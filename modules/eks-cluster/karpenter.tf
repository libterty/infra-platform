# Karpenter AWS resources. The queue, policy and rules follow the CloudFormation template of Karpenter v1.15.0
# (website/content/en/docs/getting-started/getting-started-with-karpenter/cloudformation.yaml).

locals {
  # Event patterns copied from the template: ScheduledChangeRule, SpotInterruptionRule, RebalanceRule,
  # InstanceStateChangeRule and CapacityReservationInterruptionRule.
  karpenter_events = var.karpenter == null ? {} : {
    health = {
      source      = "aws.health"
      detail_type = "AWS Health Event"
    }
    spot = {
      source      = "aws.ec2"
      detail_type = "EC2 Spot Instance Interruption Warning"
    }
    rebalance = {
      source      = "aws.ec2"
      detail_type = "EC2 Instance Rebalance Recommendation"
    }
    state = {
      source      = "aws.ec2"
      detail_type = "EC2 Instance State-change Notification"
    }
    capacity = {
      source      = "aws.ec2"
      detail_type = "EC2 Capacity Reservation Instance Interruption Warning"
    }
  }
}

resource "aws_sqs_queue" "karpenter" {
  count = var.karpenter == null ? 0 : 1

  name                      = var.name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = local.tags
}

resource "aws_sqs_queue_policy" "karpenter" {
  count = var.karpenter == null ? 0 : 1

  queue_url = aws_sqs_queue.karpenter[0].url

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "EC2InterruptionPolicy"
    Statement = [
      {
        # Narrower than the CloudFormation template, which lets any EventBridge rule send: only this module's five rules
        # may, so another account cannot feed fake interruption events to Karpenter.
        Sid       = "AllowEventBridgeRules"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.karpenter[0].arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = [for r in aws_cloudwatch_event_rule.karpenter : r.arn] }
        }
      },
      {
        Sid       = "AllowSqsService"
        Effect    = "Allow"
        Principal = { Service = "sqs.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.karpenter[0].arn
      },
      {
        Sid       = "DenyHTTP"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.karpenter[0].arn
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })
}

resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each = local.karpenter_events

  name = "${var.name}-karpenter-${each.key}"

  event_pattern = jsonencode({
    source        = [each.value.source]
    "detail-type" = [each.value.detail_type]
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each = local.karpenter_events

  rule      = aws_cloudwatch_event_rule.karpenter[each.key].name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter[0].arn
}

# Nodes Karpenter launches join through this entry. Managed node groups and Fargate profiles get theirs from EKS.
resource "aws_eks_access_entry" "karpenter_node" {
  count = var.karpenter == null ? 0 : 1

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.karpenter.node_role_arn
  type          = "EC2_LINUX"

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "karpenter" {
  count = var.karpenter == null ? 0 : 1

  cluster_name    = aws_eks_cluster.this.name
  namespace       = var.karpenter.controller_namespace
  service_account = var.karpenter.controller_service_account
  role_arn        = var.karpenter.controller_role_arn

  tags = local.tags
}
