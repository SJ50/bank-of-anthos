variable "region" {
  description = "AWS Region"
  type        = string
}
variable "environment" {
  description = "Name of environment"
  type        = string
}
variable "env_x" {
  description = "Name of environment x"
  type        = string
}
variable "solution" {
  description = "Solution, project name"
  type        = string
}
variable "vpc_name" {
  description = "Existing VPC Name"
  type = string
}
variable "redundancy" {
  description = "Redundancy across AZs"
  type        = number
  default     = 2
}
variable "psql_sg_name" {
  description = "Name of security group associated with psql rds."
  type = string
}
variable "redis_subnet_name" {
  description = "Subnets name for redis picked by data block"
  type = string
}
variable "eks_subnet_range" {
  description = "EKS Subnet ip range"
  type        = number
}
variable "cluster_addons" {
  description = "EKS Addons"
  type        = any
  default     = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }
}
variable "cluster_version" {
  description = "EKS Cluster version"
  type        = string
  default     = "1.27"
}
variable "manage_aws_auth_configmap" {
  description = "Manage AWS Auth Configmap"
  type        = bool
  default     = true
}
variable "cluster_public_endpoint" {
  description = "EKS Public endpoint"
  type        = bool
  default     = false
}
variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks which can access the Amazon EKS public API server endpoint"
  type        = list(string)
  default     = ["212.31.98.41/32", "194.42.157.1/32", "69.94.120.102/32"]
}
variable "node_group_size" {
  description = "Configuration of node group. Instance type, min,max, desired node size."
  type = object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
  })
  default = {
    instance_types = ["t3.medium"]
    min_size       = 1
    max_size       = 2
    desired_size   = 1
  }
}
variable "karpenter" {
  description = "Karpenter configuration"
  type = any
  default = {
    instance_type = ["t3.medium"]
    consolidation = false
    architecture  = ["amd64"]
    capacity_type = ["on-demand"]
  }
}
variable "node_additional_security_rules" {
  description = "Additional security rulues for node SG"
  type = any
  default = {}
}
variable "cluster_additional_security_rules" {
  description = "Additional security rulues for cluster SG"
  type = any
  default = {}
}

variable "opsvpn_peering" {
  description = "Opsvpn peering configuration"
  type = object({
    #Parameters required for existing
    peering_id  = string
    cidr        = string
    #Parameters required for creation
    create      = bool
    peer_vpc    = string
    peer_region = string
    peer_owner  = string
  })
  default = {
    create      = false
    peering_id  = ""
    cidr        = ""
    peer_vpc    = ""
    peer_region = ""
    peer_owner  = ""
  }
}

variable "bitbucket_peering" {
  description = "Bitbucket peering configuration"
  type = object({
    #Parameters required for existing
    peering_id  = string
    cidr        = string
    #Parameters required for creation
    create      = bool
    peer_vpc    = string
    peer_region = string
    peer_owner  = string
  })
  default = {
    create      = false
    peering_id  = ""
    cidr        = ""
    peer_vpc    = ""
    peer_region = ""
    peer_owner  = ""
  }
}

variable "opsfravpn_peering" {
  description = "Opsfra vpn peering configuration"
  type = object({
    #Parameters required for existing
    peering_id  = string
    cidr        = string
    #Parameters required for creation
    create      = bool
    peer_vpc    = string
    peer_region = string
    peer_owner  = string
  })
  default = {
    create      = false
    peering_id  = ""
    cidr        = ""
    peer_vpc    = ""
    peer_region = ""
    peer_owner  = ""
  }
}

variable "pbx_peering" {
  description = "Opsfra vpn peering configuration"
  type = object({
    #Parameters required for existing
    enabled     = bool
    peering_id  = string
    cidr        = string
    #Parameters required for creation
    create      = bool
    peer_vpc    = string
    peer_region = string
    peer_owner  = string
  })
  default = {
    enabled     = false
    create      = false
    peering_id  = ""
    cidr        = ""
    peer_vpc    = ""
    peer_region = ""
    peer_owner  = ""
  }
}

variable "auth_users" {
  description = "K8s users"
  type = any
  default = []
}
variable "auth_roles" {
  description = "K8s roles"
  type = any
  default = []
}
variable "log_types" {
  description = "Log types collected by CW"
  type  = list(string)
  default = []
}

variable "cert_manager" {
  description = "Cert manager configuration"
  type = any
  default = {
    create_irsa      = true
    create_release   = true
    create_namespace = true
    name             = "cert-manager"
    description      = "A Helm chart to deploy cert-manager"
    namespace        = "cert-manager"
    chart            = "cert-manager"
    chart_version    = "v1.12.3" #latest as of 21.08.2023
    repository       = "https://charts.jetstack.io"
    values           = []
    postrender       = []
    role_name        = "cert-manager"
    role_name_use_prefix = true
    role_permissions_boundary_arn = null
    role_description              = "IRSA for cert-manger project"
    role_policies                 = {}
    route53_hosted_zone_arns = ["arn:aws:route53:::hostedzone/*"]
    is_zone_private  = false
  }
}

variable "redis" {
  description = "Redis configuration"
  type = any
  default = {
    engine               = "redis"
    node_type            = "cache.t4g.micro"
    parameter_group_name = "default.redis7"
    engine_version       = "7.0.7"
    create_password      = false
  }
}

variable "database" {
  type = any
  default = null
}

variable "ingress_external" {
  description = "External/Public Ingress nginx configuration"
  type = any
  default = {
    create_namespace = false
    namespace        = "ingress-nginx"
    source_cidrs     = []
  }
}

variable "ingress_internal" {
  description = "Internal Ingress nginx configuration"
  type = any
  default = {
    create_namespace = false
    namespace        = "ingress-nginx"
  }
}

variable "custom_addons" {
  description = "Custom addons for EKS"
  type = any
  default = {
    cilium        = true
    argocd        = true
    karpenter     = true
    inflate       = true
    cert_manager  = true
    cert_le_r53   = false
    cert_le_nginx = true
    ingress_int   = false
    ingress_ext   = false
    example       = false
    aws_lb_controller = false
  }
}