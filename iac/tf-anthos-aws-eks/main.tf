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
    project        = var.project
    managed_by     = "terraform"
    team           = "devops"
    tf_path        = regexall("bank-of-anthos.*", path.cwd)[0]
    repo           = data.external.git.result.repo
    deployer       = data.external.git.result.user_name
    deployer_email = data.external.git.result.user_email
  }
}

data "aws_availability_zones" "available" {}
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

data "aws_eks_cluster_auth" "cluster-auth" {
  name = module.eks.cluster_name
}