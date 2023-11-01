data "external" "git" {
  program = ["sh", "-c", <<-EOSCRIPT
   jq -n '{ "rev": $REV, "ref": $REF, "status": $STT, "user_name": $USN, "user_email": $USE, "repo": $REP}' \
    --arg REV "$(git rev-parse --verify HEAD)" \
    --arg REF "$(git symbolic-ref HEAD || echo '(DETACHED)')" \
    --arg STT "$(git diff --quiet && echo "# CLEAN" || git status --porcelain)" \
    --arg USN "$${GIT_USER:-$(git config user.name)}" \
    --arg USE "$${GIT_USER_EMAIL:-$(git config user.email)}" \
    --arg REP "$(git remote get-url origin)"
  EOSCRIPT
  ]
}


locals {
  name                   = "${var.environment}-${var.project}-${terraform.workspace}"
  region                 = var.region
  azs                    = slice(data.aws_availability_zones.available.names, 0, var.redundancy)
  iam_role_policy_prefix = "arn:${data.aws_partition.current.partition}:iam::aws:policy"

  tags = {
    environment    = var.environment
    solution       = var.solution
    project        = var.project
    managed_by     = "terraform"
    team           = "devops"
    tf_path        = regexall("terraform-v2.*", path.cwd)[0]
    repo           = data.external.git.result.repo
    deployer       = data.external.git.result.user_name
    deployer_email = data.external.git.result.user_email
  }
}

data "aws_availability_zones" "available" {}
data "aws_partition" "current" {}

data "aws_vpc" "selected" {
  count = length(var.existing_vpc_name) > 0 ? 1 : 0
  tags = {
    Name = var.existing_vpc_name
  }
}

data "aws_nat_gateways" "selected" {
  count  = length(var.existing_vpc_name) > 0 ? 1 : 0
  vpc_id = data.aws_vpc.selected[0].id
}

data "aws_security_group" "psql" {
  count  = length(var.existing_vpc_name) > 0 ? 1 : 0
  vpc_id = data.aws_vpc.selected[0].id
  name   = var.psql_sg_name
}

data "aws_eks_cluster_auth" "cluster-auth" {
  name = module.eks.cluster_name
}

data "aws_subnets" "psql" {
  count = length(var.existing_vpc_name) > 0 ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected[0].id]
  }
  tags = {
    Name = var.database.subnet_name
  }
}