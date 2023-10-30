################################################################################
# Cluster
################################################################################
#tfsec:ignore:aws-eks-enable-control-plane-logging
module "eks" {
  source                               = "../../../modules/aws/eks"
  cluster_name                         = "${var.environment}-${var.solution}-${terraform.workspace}"
  cluster_version                      = var.cluster_version
  cluster_endpoint_public_access       = var.cluster_public_endpoint
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  vpc_id                               = data.aws_vpc.selected.id
  subnet_ids                           = aws_subnet.private[*].id
  cluster_enabled_log_types            = var.log_types
  enable_irsa                          = true
  redundancy                           = var.redundancy
  environment                          = var.environment
  cluster_addons                       = var.cluster_addons
  custom_addons                        = var.custom_addons
  karpenter                            = var.karpenter
  cert_manager                         = var.cert_manager
  region                               = var.region
  ingress_external                     = var.ingress_external
  ingress_internal                     = var.ingress_internal
# Remote ssh access to nodes
#  eks_managed_node_group_defaults = {
#    remote_access = {
#      ec2_ssh_key = ""
#      source_security_group_ids = [""]
#    }
#  }

  # Initial node group config
  eks_managed_node_groups = {
    initial = var.node_group_size
  }
  manage_aws_auth_configmap = var.manage_aws_auth_configmap
  # Entries in aws-auth config map for IAM users
  aws_auth_users = var.auth_users
  aws_auth_roles = concat(
    [
      {
        # Entry in aws-auth config map for karpenter IAM role
        rolearn  = module.eks.karpenter.node_iam_role_arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      }
    ],
    var.auth_roles
  )

  # Extend cluster security group rules
  cluster_security_group_additional_rules = merge(
    {
      node_to_eks_api = {
        description = "Node to EKS api"
        protocol    = "-1"
        from_port   = 0
        to_port     = 0
        type        = "ingress"
        source_security_group_id = module.eks.node_security_group_id
      }
    },
    var.cluster_additional_security_rules
  )
  # Extend node security group
  node_security_group_additional_rules    = merge(
    var.node_additional_security_rules,
    {
      eks_to_psql = {
        description = "EKS to psql"
        protocol    = "tcp"
        from_port   = 5432
        to_port     = 5432
        type        = "egress"
        source_security_group_id = var.environment == "test" ? aws_security_group.psql[0].id : data.aws_security_group.psql.id
      }
      eks_to_redis = {
        description = "EKS to redis"
        protocol    = "tcp"
        from_port   = "6379"
        to_port     = "6379"
        type        = "egress"
        source_security_group_id = aws_security_group.redis.id
      }
    }
  )

  # Node SG tags
  node_security_group_tags = {
    #Additional tags for karpenter autoscaling
    "kubernetes.io/cluster/${local.name}" = "owned"
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery" = local.name
  }
  # Cluster SG tags
  cluster_security_group_tags = {
    "kubernetes.io/cluster/${local.name}" = "owned"
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags

}

