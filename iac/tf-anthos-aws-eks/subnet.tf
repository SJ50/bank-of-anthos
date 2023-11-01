resource "aws_subnet" "private" {
  count                   = var.redundancy
  vpc_id                  = data.aws_vpc.selected.id
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = cidrsubnet(data.aws_vpc.selected.cidr_block, 8, var.eks_subnet_range + count.index)
  map_public_ip_on_launch = false

  tags = merge(
    {
      Name = join("-", [var.environment, var.solution, "eks-internal", terraform.workspace]),
    },
    local.tags,
    {
      "kubernetes.io/cluster/${local.name}" = "owned"
    },
    {
      "kubernetes.io/role/internal-elb" = 1
    },
    {
      "karpenter.sh/discovery" = local.name
    }
  )
}

resource "aws_route_table" "eks_to_nat" {
  count = var.redundancy

  vpc_id = data.aws_vpc.selected.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = element(data.aws_nat_gateways.selected.ids, count.index)
  }

  lifecycle {
    ignore_changes = [route]
  }

  tags = {
    Name = "${var.environment}-${var.solution}-${terraform.workspace}-nat"
  }
}

resource "aws_route_table_association" "this" {
  count = var.redundancy

  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.eks_to_nat.*.id, count.index)
}

resource "aws_network_acl" "this" {
  count      = var.redundancy
  vpc_id     = data.aws_vpc.selected.id
  subnet_ids = [aws_subnet.private[count.index].id]

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name         = "${var.environment}-${var.solution}-eks-internal-${terraform.workspace}-nacl"
    managed_by   = "terraform"
    environment  = var.environment
    tf_workspace = terraform.workspace
  }
}



#SG Rule to access rabbitMQ from EKS
resource "aws_security_group_rule" "eks_to_rabbit" {
  count                    = var.environment == "stage" ? 1 : 0
  security_group_id        = data.aws_security_group.rabbit[0].id
  from_port                = 5671
  description              = "Allow access from finops eks cluster to rabbitmq"
  protocol                 = "tcp"
  to_port                  = 5671
  type                     = "ingress"
  source_security_group_id = module.eks.node_security_group_id
}