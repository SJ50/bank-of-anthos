data "aws_availability_zones" "available" {}
data "aws_partition" "current" {}

data "aws_vpc" "selected" {
  tags = {
    Name = var.vpc_name
  }
}

data "aws_security_group" "psql" {
  vpc_id = data.aws_vpc.selected.id
  name = var.psql_sg_name
}
data "aws_security_group" "rabbit" {
  count = var.environment == "stage" ? 1 : 0
  vpc_id = data.aws_vpc.selected.id
  name = "${var.environment}-pbx-RabbitMQ-${terraform.workspace}*"
}

data "aws_nat_gateways" "selected" {
  vpc_id = data.aws_vpc.selected.id
}

data "aws_eks_cluster_auth" "cluster-auth" {
  name       = module.eks.cluster_name
}

data  "aws_subnets" "rabbit" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  tags = {
    Name = var.redis_subnet_name
  }
}

data  "aws_subnets" "psql" {
  count = var.environment == "test" ? 1 : 0
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  tags = {
    Name = var.database.subnet_name
  }
}

locals {
  name   = "${var.environment}-finops-${terraform.workspace}"
  region = var.region
  azs      = slice(data.aws_availability_zones.available.names, 0, var.redundancy)
  psql_subnets = var.environment == "test" ? slice(data.aws_subnets.psql[0].ids, 0, var.redundancy) : null
  iam_role_policy_prefix = "arn:${data.aws_partition.current.partition}:iam::aws:policy"

  tags = {
    environment = var.environment
    env_x       = var.env_x
    solution    = var.solution
    project     = var.solution
    managed_by  = "terraform"

  }
}