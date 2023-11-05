environment = "test"
region      = "ap-southeast-2"
project     = "boa"
cluster_addons = {
  coredns = {
    preserve    = true
    most_recent = true

    timeouts = {
      create = "25m"
      delete = "10m"
    }
  }
  kube-proxy = {
    most_recent = true
  }
  vpc-cni = {
    most_recent = true
  }
}
database = {
  instance_use_identifier_prefix        = false
  engine                                = "postgres"
  engine_version                        = "15.4"
  family                                = "postgres15"
  major_engine_version                  = "15"
  allow_major_version_upgrade           = true
  apply_immediately                     = true
  instance_class                        = "db.t4g.micro"
  storage_type                          = "gp2"
  iops                                  = null
  storage_throughput                    = null
  allocated_storage                     = 20
  max_allocated_storage                 = 100
  ca_cert_identifier                    = "rds-ca-rsa2048-g1"
  username                              = "dbadmin"
  password                              = "dbpassword_changeme"
  port                                  = 5432
  iam_database_authentication_enabled   = false
  multi_az                              = false
  maintenance_window                    = "sun:02:05-sun:05:00" # total duration should be less than 24 hr.
  backup_window                         = "00:00-02:00"
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]
  create_cloudwatch_log_group           = true
  backup_retention_period               = 7
  skip_final_snapshot                   = true
  deletion_protection                   = true
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  create_monitoring_role                = true
  monitoring_interval                   = 60
  monitoring_role_use_name_prefix       = false
  create_db_parameter_group             = true
  parameter_group_use_name_prefix       = true
  parameter_group_description           = "Managed by Terraform"
  parameters = [
    {
      name  = "autovacuum"
      value = 1
    },
    {
      name  = "client_encoding"
      value = "utf8"
    }
  ]
  create_db_subnet_group          = true
  db_subnet_group_use_name_prefix = false
  db_subnet_group_description     = "Managed by Terraform"
}