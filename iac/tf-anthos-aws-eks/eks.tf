################################################################################
# Cluster
################################################################################
module "eks" {
  # https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name                         = local.name
  cluster_endpoint_public_access       = var.cluster_public_endpoint
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  cluster_addons = var.cluster_addons

  # External encryption key
  create_kms_key = var.create_kms_key
  cluster_encryption_config = {
    resources        = ["secrets"]
    provider_key_arn = module.kms.key_arn
  }

  iam_role_additional_policies = {
    additional = aws_iam_policy.additional.arn
  }


  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = moduel.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  cluster_enabled_log_types = var.cluster_enabled_log_types
  enable_irsa               = var.enable_irsa

  # Extend cluster security group rules
  cluster_security_group_additional_rules = merge(
    {
      node_to_eks_api = {
        description              = "Node to EKS api"
        protocol                 = "-1"
        from_port                = 0
        to_port                  = 0
        type                     = "ingress"
        source_security_group_id = module.eks.node_security_group_id
      }
      ingress_nodes_ephemeral_ports_tcp = {
        description                = "Nodes on ephemeral ports"
        protocol                   = "tcp"
        from_port                  = 1025
        to_port                    = 65535
        type                       = "ingress"
        source_node_security_group = true
      }
      # Test: https://github.com/terraform-aws-modules/terraform-aws-eks/pull/2319
      ingress_source_security_group_id = {
        description              = "Ingress from another computed security group"
        protocol                 = "tcp"
        from_port                = 22
        to_port                  = 22
        type                     = "ingress"
        source_security_group_id = aws_security_group.additional.id
      }
    },
    var.cluster_additional_security_rules
  )
  # Extend node security group
  node_security_group_additional_rules = merge(
    var.node_additional_security_rules,
    {
      eks_to_psql = {
        description              = "EKS to psql"
        protocol                 = "tcp"
        from_port                = 5432
        to_port                  = 5432
        type                     = "egress"
        source_security_group_id = var.environment == "test" ? aws_security_group.psql[0].id : data.aws_security_group.psql.id
      }
      ingress_self_all = {
        description = "Node to node all ports/protocols"
        protocol    = "-1"
        from_port   = 0
        to_port     = 0
        type        = "ingress"
        self        = true
      }
      # Test: https://github.com/terraform-aws-modules/terraform-aws-eks/pull/2319
      ingress_source_security_group_id = {
        description              = "Ingress from another computed security group"
        protocol                 = "tcp"
        from_port                = 22
        to_port                  = 22
        type                     = "ingress"
        source_security_group_id = aws_security_group.additional.id
      }
    }
  )


  cert_manager     = var.cert_manager
  region           = var.region
  ingress_external = var.ingress_external
  ingress_internal = var.ingress_internal
  # Remote ssh access to nodes
  #  eks_managed_node_group_defaults = {
  #    remote_access = {
  #      ec2_ssh_key = ""
  #      source_security_group_ids = [""]
  #    }
  #  }

  # Self Managed Node Group(s)
  self_managed_node_group_defaults = {
    vpc_security_group_ids = [aws_security_group.additional.id]
    iam_role_additional_policies = {
      additional = aws_iam_policy.additional.arn
    }

    instance_refresh = {
      strategy = "Rolling"
      preferences = {
        min_healthy_percentage = 66
      }
    }
  }

  self_managed_node_groups = {
    spot = {
      instance_type = "m5.large"
      instance_market_options = {
        market_type = "spot"
      }

      pre_bootstrap_user_data = <<-EOT
        echo "foo"
        export FOO=bar
      EOT

      bootstrap_extra_args = "--kubelet-extra-args '--node-labels=node.kubernetes.io/lifecycle=spot'"

      post_bootstrap_user_data = <<-EOT
        cd /tmp
        sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
        sudo systemctl enable amazon-ssm-agent
        sudo systemctl start amazon-ssm-agent
      EOT
    }
  }

  # EKS Managed Node Group(s)
  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"
    instance_types = ["m6i.large", "m5.large", "m5n.large", "m5zn.large"]

    attach_cluster_primary_security_group = true
    vpc_security_group_ids                = [aws_security_group.additional.id]
    iam_role_additional_policies = {
      additional = aws_iam_policy.additional.arn
    }
  }

  eks_managed_node_groups = {
    blue = {}
    green = {
      min_size     = 1
      max_size     = 10
      desired_size = 1

      instance_types = ["t3.large"]
      capacity_type  = "SPOT"
      labels = {
        Environment = "test"
        GithubRepo  = "terraform-aws-eks"
        GithubOrg   = "terraform-aws-modules"
      }

      taints = {
        dedicated = {
          key    = "dedicated"
          value  = "gpuGroup"
          effect = "NO_SCHEDULE"
        }
      }

      update_config = {
        max_unavailable_percentage = 33 # or set `max_unavailable`
      }

      tags = {
        ExtraTag = "example"
      }
    }
  }

  # Fargate Profile(s)
  fargate_profiles = {
    default = {
      name = "default"
      selectors = [
        {
          namespace = "kube-system"
          labels = {
            k8s-app = "kube-dns"
          }
        },
        {
          namespace = "default"
        }
      ]

      tags = {
        Owner = "test"
      }

      timeouts = {
        create = "20m"
        delete = "20m"
      }
    }
  }

  # Create a new cluster where both an identity provider and Fargate profile is created
  # will result in conflicts since only one can take place at a time
  # # OIDC Identity provider
  # cluster_identity_providers = {
  #   sts = {
  #     client_id = "sts.amazonaws.com"
  #   }
  # }

  manage_aws_auth_configmap = var.manage_aws_auth_configmap
  aws_auth_node_iam_role_arns_non_windows = [
    module.eks_managed_node_group.iam_role_arn,
    module.self_managed_node_group.iam_role_arn,
  ]
  aws_auth_fargate_profile_pod_execution_role_arns = [
    module.fargate_profile.fargate_profile_pod_execution_role_arn
  ]

  # Entries in aws-auth config map for IAM users
  aws_auth_users = concat([], var.aws_auth_users)
  aws_auth_roles = concat(
    [
      {
        # Entry in aws-auth config map for karpenter IAM role
        rolearn  = module.karpenter.role_arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups = [
          "system:bootstrappers",
          "system:nodes",
        ]
      },
    ],
    var.aws_auth_roles
  )



  # Node SG tags
  node_security_group_tags = {
    #Additional tags for karpenter autoscaling
    "kubernetes.io/cluster/${local.name}" = "owned"
    "kubernetes.io/role/internal-elb"     = 1
    "karpenter.sh/discovery"              = local.name
  }
  # Cluster SG tags
  cluster_security_group_tags = {
    "kubernetes.io/cluster/${local.name}" = "owned"
    "kubernetes.io/role/internal-elb"     = 1
  }

  tags = local.tags

}