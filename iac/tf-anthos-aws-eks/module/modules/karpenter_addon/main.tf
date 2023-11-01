data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# This resource is used to provide a means of mapping an implicit dependency
# between the cluster and the addons.
resource "time_sleep" "this" {
  create_duration = var.create_delay_duration

  triggers = {
    cluster_endpoint  = var.cluster_endpoint
    cluster_name      = var.cluster_name
    custom            = join(",", var.create_delay_dependencies)
    oidc_provider_arn = var.oidc_provider_arn
  }
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  dns_suffix = data.aws_partition.current.dns_suffix
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name

  # Threads the sleep resource into the module to make the dependency
  cluster_endpoint  = time_sleep.this.triggers["cluster_endpoint"]
  cluster_name      = time_sleep.this.triggers["cluster_name"]
  oidc_provider_arn = time_sleep.this.triggers["oidc_provider_arn"]

  iam_role_policy_prefix = "arn:${local.partition}:iam::aws:policy"

  # Used by Karpenter & AWS Node Termination Handler
  ec2_events = {
    health_event = {
      name        = "HealthEvent"
      description = "AWS health event"
      event_pattern = {
        source      = ["aws.health"]
        detail-type = ["AWS Health Event"]
      }
    }
    spot_interupt = {
      name        = "SpotInterrupt"
      description = "EC2 spot instance interruption warning"
      event_pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Spot Instance Interruption Warning"]
      }
    }
    instance_rebalance = {
      name        = "InstanceRebalance"
      description = "EC2 instance rebalance recommendation"
      event_pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance Rebalance Recommendation"]
      }
    }
    instance_state_change = {
      name        = "InstanceStateChange"
      description = "EC2 instance state-change notification"
      event_pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance State-change Notification"]
      }
    }
  }
}

################################################################################
# Karpenter
################################################################################

locals {
  karpenter_service_account_name    = try(var.karpenter.service_account_name, "karpenter")
  karpenter_enable_spot_termination = var.enable_karpenter && var.karpenter_enable_spot_termination

  create_karpenter_node_iam_role = var.enable_karpenter && try(var.karpenter_node.create_iam_role, true)
  karpenter_node_iam_role_arn    = try(aws_iam_role.karpenter[0].arn, var.karpenter_node.iam_role_arn, "")
  karpenter_node_iam_role_name   = try(var.karpenter_node.iam_role_name, "karpenter-${var.cluster_name}")
}

data "aws_iam_policy_document" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  statement {
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
    ]
    resources = ["*"]
  }

  statement {
    actions = [
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateTags",
      "ec2:DeleteLaunchTemplate",
      "ec2:RunInstances"
    ]
    resources = [
      "arn:${local.partition}:ec2:${local.region}:${local.account_id}:*",
      "arn:${local.partition}:ec2:${local.region}::image/*"
    ]
  }

  statement {
    actions   = ["iam:PassRole"]
    resources = [local.karpenter_node_iam_role_arn]
  }

  statement {
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  statement {
    actions   = ["ssm:GetParameter"]
    resources = ["arn:${local.partition}:ssm:${local.region}::parameter/*"]
  }

  statement {
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:${local.partition}:eks:*:${local.account_id}:cluster/${var.cluster_name}"]
  }

  statement {
    actions   = ["ec2:TerminateInstances"]
    resources = ["arn:${local.partition}:ec2:${local.region}:${local.account_id}:instance/*"]

    condition {
      test     = "StringLike"
      variable = "ec2:ResourceTag/Name"
      values   = ["*karpenter*"]
    }
  }

  dynamic "statement" {
    for_each = var.karpenter_enable_spot_termination ? [1] : []

    content {
      actions = [
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
        "sqs:ReceiveMessage",
      ]
      resources = [module.karpenter_sqs.queue_arn]
    }
  }
}

module "karpenter_sqs" {
  source = "../karpenter_sqs"

  create = local.karpenter_enable_spot_termination

  name = try(var.karpenter_sqs.queue_name, "karpenter-${var.cluster_name}")

  message_retention_seconds         = try(var.karpenter_sqs.message_retention_seconds, 300)
  sqs_managed_sse_enabled           = try(var.karpenter_sqs.sse_enabled, true)
  kms_master_key_id                 = try(var.karpenter_sqs.kms_master_key_id, null)
  kms_data_key_reuse_period_seconds = try(var.karpenter_sqs.kms_data_key_reuse_period_seconds, null)

  create_queue_policy = true
  queue_policy_statements = {
    account = {
      sid     = "SendEventsToQueue"
      actions = ["sqs:SendMessage"]
      principals = [
        {
          type = "Service"
          identifiers = [
            "events.${local.dns_suffix}",
            "sqs.${local.dns_suffix}",
          ]
        }
      ]
    }
  }

  tags = merge(var.tags, try(var.karpenter_sqs.tags, {}))
}

resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each = { for k, v in local.ec2_events : k => v if local.karpenter_enable_spot_termination }

  name_prefix   = "Karpenter-${each.value.name}-"
  description   = each.value.description
  event_pattern = jsonencode(each.value.event_pattern)

  tags = merge(
    { "ClusterName" : var.cluster_name },
    var.tags,
  )
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each = { for k, v in local.ec2_events : k => v if local.karpenter_enable_spot_termination }

  rule      = aws_cloudwatch_event_rule.karpenter[each.key].name
  target_id = "KarpenterQueueTarget"
  arn       = module.karpenter_sqs.queue_arn
}

data "aws_iam_policy_document" "karpenter_assume_role" {
  count = local.create_karpenter_node_iam_role ? 1 : 0

  statement {
    sid     = "KarpenterNodeAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.${local.dns_suffix}"]
    }
  }
}

resource "aws_iam_role" "karpenter" {
  count = local.create_karpenter_node_iam_role ? 1 : 0

  name        = try(var.karpenter_node.iam_role_use_name_prefix, true) ? null : local.karpenter_node_iam_role_name
  name_prefix = try(var.karpenter_node.iam_role_use_name_prefix, true) ? "${local.karpenter_node_iam_role_name}-" : null
  path        = try(var.karpenter_node.iam_role_path, null)
  description = try(var.karpenter_node.iam_role_description, "Karpenter EC2 node IAM role")

  assume_role_policy    = try(data.aws_iam_policy_document.karpenter_assume_role[0].json, "")
  max_session_duration  = try(var.karpenter_node.iam_role_max_session_duration, null)
  permissions_boundary  = try(var.karpenter_node.iam_role_permissions_boundary, null)
  force_detach_policies = true

  tags = merge(var.tags, try(var.karpenter_node.iam_role_tags, {}))
}

resource "aws_iam_role_policy_attachment" "karpenter" {
  for_each = { for k, v in {
    AmazonEKSWorkerNodePolicy            = "${local.iam_role_policy_prefix}/AmazonEKSWorkerNodePolicy",
    AmazonEC2ContainerRegistryFullAccess = "${local.iam_role_policy_prefix}/AmazonEC2ContainerRegistryFullAccess",
    AmazonEKS_CNI_Policy                 = "${local.iam_role_policy_prefix}/AmazonEKS_CNI_Policy"
    AmazonEBSCreate                      = "${local.iam_role_policy_prefix}/service-role/AmazonEBSCSIDriverPolicy"
  } : k => v if local.create_karpenter_node_iam_role }

  policy_arn = each.value
  role       = aws_iam_role.karpenter[0].name
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = { for k, v in try(var.karpenter_node.iam_role_additional_policies, {}) : k => v if local.create_karpenter_node_iam_role }

  policy_arn = each.value
  role       = aws_iam_role.karpenter[0].name
}

resource "aws_iam_instance_profile" "karpenter" {
  count = var.enable_karpenter && try(var.karpenter_node.create_instance_profile, true) ? 1 : 0

  name        = try(var.karpenter_node.iam_role_use_name_prefix, true) ? null : local.karpenter_node_iam_role_name
  name_prefix = try(var.karpenter_node.iam_role_use_name_prefix, true) ? "${local.karpenter_node_iam_role_name}-" : null
  path        = try(var.karpenter_node.iam_role_path, null)
  role        = try(aws_iam_role.karpenter[0].name, var.karpenter_node.iam_role_name, "")

  tags = merge(var.tags, try(var.karpenter_node.instance_profile_tags, {}))
}

module "karpenter" {
  source = "../karpenter"
  //version = "1.1.0"

  create = var.enable_karpenter

  # https://github.com/aws/karpenter/blob/main/charts/karpenter/Chart.yaml
  name             = try(var.karpenter.name, "karpenter")
  description      = try(var.karpenter.description, "A Helm chart to deploy Karpenter")
  namespace        = try(var.karpenter.namespace, "karpenter")
  create_namespace = try(var.karpenter.create_namespace, true)
  chart            = try(var.karpenter.chart, "karpenter")
  chart_version    = try(var.karpenter.chart_version, "v0.29.2")
  repository       = try(var.karpenter.repository, "oci://public.ecr.aws/karpenter")
  values           = try(var.karpenter.values, [])

  timeout                    = try(var.karpenter.timeout, null)
  repository_key_file        = try(var.karpenter.repository_key_file, null)
  repository_cert_file       = try(var.karpenter.repository_cert_file, null)
  repository_ca_file         = try(var.karpenter.repository_ca_file, null)
  repository_username        = try(var.karpenter.repository_username, null)
  repository_password        = try(var.karpenter.repository_password, null)
  devel                      = try(var.karpenter.devel, null)
  verify                     = try(var.karpenter.verify, null)
  keyring                    = try(var.karpenter.keyring, null)
  disable_webhooks           = try(var.karpenter.disable_webhooks, null)
  reuse_values               = try(var.karpenter.reuse_values, null)
  reset_values               = try(var.karpenter.reset_values, null)
  force_update               = try(var.karpenter.force_update, null)
  recreate_pods              = try(var.karpenter.recreate_pods, null)
  cleanup_on_fail            = try(var.karpenter.cleanup_on_fail, null)
  max_history                = try(var.karpenter.max_history, null)
  atomic                     = try(var.karpenter.atomic, null)
  skip_crds                  = try(var.karpenter.skip_crds, null)
  render_subchart_notes      = try(var.karpenter.render_subchart_notes, null)
  disable_openapi_validation = try(var.karpenter.disable_openapi_validation, null)
  wait                       = try(var.karpenter.wait, false)
  wait_for_jobs              = try(var.karpenter.wait_for_jobs, null)
  dependency_update          = try(var.karpenter.dependency_update, null)
  replace                    = try(var.karpenter.replace, null)
  lint                       = try(var.karpenter.lint, null)

  postrender = try(var.karpenter.postrender, [])
  set = concat(
    [
      {
        name  = "settings.aws.clusterName"
        value = local.cluster_name
      },
      {
        name  = "settings.aws.clusterEndpoint"
        value = local.cluster_endpoint
      },
      {
        name  = "settings.aws.enablePodENI"
        value = true
      },
      {
        name  = "settings.aws.defaultInstanceProfile"
        value = try(aws_iam_instance_profile.karpenter[0].name, var.karpenter_node.instance_profile_name, "")
      },
      {
        name  = "settings.aws.interruptionQueueName"
        value = module.karpenter_sqs.queue_name
      },
      {
        name  = "serviceAccount.name"
        value = local.karpenter_service_account_name
      },
    ],
    try(var.karpenter.set, [])
  )
  set_sensitive = try(var.karpenter.set_sensitive, [])

  # IAM role for service account (IRSA)
  set_irsa_names                = ["serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"]
  create_role                   = try(var.karpenter.create_role, true)
  role_name                     = try(var.karpenter.role_name, "karpenter")
  role_name_use_prefix          = try(var.karpenter.role_name_use_prefix, true)
  role_path                     = try(var.karpenter.role_path, "/")
  role_permissions_boundary_arn = lookup(var.karpenter, "role_permissions_boundary_arn", null)
  role_description              = try(var.karpenter.role_description, "IRSA for Karpenter")
  role_policies                 = lookup(var.karpenter, "role_policies", {})

  source_policy_documents = compact(concat(
    data.aws_iam_policy_document.karpenter[*].json,
    lookup(var.karpenter, "source_policy_documents", [])
  ))
  override_policy_documents = lookup(var.karpenter, "override_policy_documents", [])
  policy_statements         = lookup(var.karpenter, "policy_statements", [])
  policy_name               = try(var.karpenter.policy_name, null)
  policy_name_use_prefix    = try(var.karpenter.policy_name_use_prefix, true)
  policy_path               = try(var.karpenter.policy_path, null)
  policy_description        = try(var.karpenter.policy_description, "IAM Policy for karpenter")

  oidc_providers = {
    this = {
      provider_arn = local.oidc_provider_arn
      # namespace is inherited from chart
      service_account = local.karpenter_service_account_name
    }
  }

  tags = var.tags
}
