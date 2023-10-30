module "db" {
  count = var.environment == "test" ? 1 : 0
  source = "../../../modules/aws/aws_rds"

  identifier                     = local.name # ! this is cluster name
  instance_use_identifier_prefix = false
  # All available versions: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts
  engine               = var.database.engine
  engine_version       = var.database.engine_version
  family               = var.database.family               # DB parameter group
  major_engine_version = var.database.major_engine_version # DB option group
  instance_class       = var.database.instance_class

  storage_type          = var.database.storage_type
  iops                  = var.database.iops
  storage_throughput    = var.database.storage_throughput
  allocated_storage     = var.database.allocated_storage
  max_allocated_storage = var.database.max_allocated_storage

  # NOTE: Do NOT use 'user' as the value for 'username' as it throws:
  # "Error creating DB Instance: InvalidParameterValue: MasterUsername
  # user cannot be used as it is a reserved word used by the engine"
  db_name                             = "finops" # ! this is internal database name, not cluster name.
  username                            = var.database.username
  port                                = var.database.port
  iam_database_authentication_enabled = var.database.iam_database_authentication_enabled

  multi_az = var.database.multi_az
  # db_subnet_group_name   = local.name # this must be the same subnet as the documentdb
  create_db_subnet_group          = var.database.create_db_subnet_group
  db_subnet_group_name            = "test-finops-default"
  db_subnet_group_use_name_prefix = var.database.db_subnet_group_use_name_prefix
  db_subnet_group_description     = var.database.db_subnet_group_description
  subnet_ids = local.psql_subnets
  vpc_security_group_ids = [aws_security_group.psql[0].id]

  maintenance_window              = var.database.maintenance_window
  backup_window                   = var.database.backup_window
  enabled_cloudwatch_logs_exports = var.database.enabled_cloudwatch_logs_exports
  create_cloudwatch_log_group     = var.database.create_cloudwatch_log_group

  backup_retention_period = var.database.backup_retention_period
  skip_final_snapshot     = var.database.skip_final_snapshot
  deletion_protection     = var.database.deletion_protection

  performance_insights_enabled          = var.database.performance_insights_enabled
  performance_insights_retention_period = var.database.performance_insights_retention_period
  create_monitoring_role                = var.database.create_monitoring_role

  create_db_parameter_group       = var.database.create_db_parameter_group
  parameter_group_use_name_prefix = var.database.parameter_group_use_name_prefix
  parameter_group_description     = var.database.parameter_group_description
  parameters                      = var.database.parameters
  db_parameter_group_tags = {
    "created by" = "terraform submodule"
  }
  create_random_password = var.database.create_random_password
  password = var.database.password

  tags = local.tags
}

resource "aws_security_group" "psql" {
  count = var.environment == "test" ? 1 : 0
  name        = local.name
  description = "${var.environment} ${var.solution} psql"
  vpc_id      = data.aws_vpc.selected.id
  tags        = local.tags
}

resource "aws_security_group_rule" "psql_to_eks" {
  count = var.environment == "test" ? 1 : 0
  security_group_id = aws_security_group.psql[0].id
  from_port         = 0
  description       = "Allow access from finops eks cluster to rabbitmq"
  protocol          = "-1"
  to_port           = 0
  type              = "egress"
  source_security_group_id = module.eks.node_security_group_id
}

#SG Rule to access issuing psql from eks
resource "aws_security_group_rule" "eks_to_psql" {
  security_group_id = var.environment == "test" ? aws_security_group.psql[0].id : data.aws_security_group.psql.id
  from_port         = 5432
  protocol          = "tcp"
  to_port           = 5432
  type              = "ingress"
  description       = "Allow access from finops eks cluster to psql"
  source_security_group_id = module.eks.node_security_group_id
}

resource "aws_security_group_rule" "office_psql" {
  count = var.environment == "test" ? 1 : 0
  security_group_id = aws_security_group.psql[0].id
  from_port         = 0
  description       = "Allow access from office"
  protocol          = "-1"
  to_port           = 0
  type              = "ingress"
  cidr_blocks = ["212.31.98.41/32"]
}