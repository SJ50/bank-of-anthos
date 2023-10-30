provider "aws" {
  region = "us-east-1"
  alias = "public-ecr"
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.public-ecr
}

module "karpenter" {
  count = var.custom_addons.karpenter ? 1 : 0
  source = "./modules/karpenter_addon"

  cluster_name      = try(aws_eks_cluster.this[0].name, "")
  cluster_endpoint  = try(aws_eks_cluster.this[0].endpoint, null)
  cluster_version   = try(aws_eks_cluster.this[0].version, null)
  oidc_provider_arn = try(aws_iam_openid_connect_provider.oidc_provider[0].arn, null)

  enable_karpenter = true
  karpenter = {
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  tags = var.tags
}

################################################################################
# Karpenter
################################################################################

resource "kubectl_manifest" "karpenter_provisioner" {
  count = var.custom_addons.karpenter ? 1 : 0
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1alpha5
    kind: Provisioner
    metadata:
      name: default
    spec:
      requirements:
        - key: "node.kubernetes.io/instance-type" #If not included, all instance types are considered
          operator: In
          values: ${jsonencode(var.karpenter.instance_type)}
        - key: "topology.kubernetes.io/zone"
          operator: In
          values: ${jsonencode(local.azs)}
        - key: "kubernetes.io/arch"
          operator: In
          values: ${jsonencode(var.karpenter.architecture)}
        - key: "karpenter.sh/capacity-type" # If not included, the webhook for the AWS cloud provider will default to on-demand
          operator: In
          values: ${jsonencode(var.karpenter.capacity_type)}
      kubeletConfiguration:
        containerRuntime: containerd
        maxPods: 110
      limits:
        resources:
          cpu: 1000  #In mili, 1000 = 1cpu
      consolidation:
        enabled: ${jsonencode(var.karpenter.consolidation)}
      providerRef:
        name: default
      ttlSecondsUntilExpired: 604800 # 7 Days = 7 * 24 * 60 * 60 Seconds
      ttlSecondsAfterEmpty: 30 #comment when consolidation.enabled = true
  YAML

  depends_on = [
    module.karpenter
  ]
}

resource "kubectl_manifest" "karpenter_node_template" {
  count = var.custom_addons.karpenter ? 1 : 0
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1alpha1
    kind: AWSNodeTemplate
    metadata:
      name: default
    spec:
      subnetSelector:
        karpenter.sh/discovery: ${try(aws_eks_cluster.this[0].name, "")}
      securityGroupSelector:
        karpenter.sh/discovery: ${try(aws_eks_cluster.this[0].name, "")}
      instanceProfile: ${module.karpenter[0].karpenter.node_instance_profile_name}
      tags:
        karpenter.sh/discovery: ${try(aws_eks_cluster.this[0].name, "")}
  YAML

  depends_on = [
    module.karpenter
  ]
}


