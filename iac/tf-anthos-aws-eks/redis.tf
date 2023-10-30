################# ELASTICACHE REDIS ##############

resource "aws_security_group" "redis" {
  name        = "${local.name}-redis"
  description = "Finops Redis Security Group"
  vpc_id      = data.aws_vpc.selected.id

  tags = local.tags
}

resource "aws_security_group_rule" "eks_to_redis" {
  from_port         = 0
  protocol          = "-1"
  security_group_id = aws_security_group.redis.id
  to_port           = -1
  type              = "ingress"
  description       = "Allow eks to redis connection"
  source_security_group_id = module.eks.node_security_group_id
}

resource "aws_security_group_rule" "redis_to_eks" {
  from_port         = 0
  protocol          = "-1"
  security_group_id = aws_security_group.redis.id
  to_port           = 0
  type              = "egress"
  description       = "Allow egress to eks connection"
  source_security_group_id = module.eks.node_security_group_id
}

module "redis" {
  source          = "../../../modules/aws/elasticache_redis_7"
  name            = local.name
  subnet_ids      = data.aws_subnets.rabbit.ids
  node_type       = var.redis.node_type
  engine_version  = var.redis.engine_version
  create_password = var.redis.create_password
  parameter_group_name = var.redis.parameter_group_name
  security_group_ids   = [aws_security_group.redis.id]

  tags_all = local.tags
}