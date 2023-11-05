module "db" {

  source  = "terraform-aws-modules/rds/aws"
  version = "6.2.0"

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
  db_name                             = var.project # ! this is internal database name, not cluster name.
  username                            = var.database.username
  port                                = var.database.port
  iam_database_authentication_enabled = var.database.iam_database_authentication_enabled

  multi_az               = var.database.multi_az
  db_subnet_group_name   = module.vpc.database_subnet_group
  vpc_security_group_ids = [module.security_group.security_group_id]

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
  db_parameter_group_tags = merge(
    local.tags,
    {
      "created by" = "terraform submodule"
  })

  password = var.database.password

  tags = local.tags
}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = local.name
  description = "PostgreSQL security group"
  vpc_id      = module.vpc.vpc_id

  # ingress
  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "PostgreSQL access from within VPC"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
  ]

  tags = local.tags
}