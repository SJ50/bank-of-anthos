##Peering to Sydney utils (bitbucket)
resource "aws_vpc_peering_connection" "bitbucket" {
  count         = var.bitbucket_peering.create ? 1 : 0
  peer_region   = var.bitbucket_peering.peer_region
  peer_owner_id = var.bitbucket_peering.peer_owner
  peer_vpc_id   = var.bitbucket_peering.peer_vpc
  vpc_id        = data.aws_vpc.selected.id
  tags = {
    Name = "bitbucket_sydney"
  }
}
resource "aws_route" "local-to-bitbucket" {
  count                     = var.redundancy
  route_table_id            = element(aws_route_table.eks_to_nat.*.id, count.index)
  destination_cidr_block    = var.bitbucket_peering.cidr
  vpc_peering_connection_id = var.bitbucket_peering.create ? aws_vpc_peering_connection.bitbucket[0].id : var.bitbucket_peering.peering_id
}

##Peering to OPS VPN
resource "aws_vpc_peering_connection" "ops_vpn" {
  count         = var.opsvpn_peering.create ? 1 : 0
  peer_region   = var.opsvpn_peering.peer_region
  peer_owner_id = var.opsvpn_peering.peer_owner
  peer_vpc_id   = var.opsvpn_peering.peer_vpc
  vpc_id        = data.aws_vpc.selected.id
  tags = {
    Name = "ops_vpn"
  }
}
resource "aws_route" "local-to-ops-vpn" {
  count                     = var.redundancy
  route_table_id            = element(aws_route_table.eks_to_nat.*.id, count.index)
  destination_cidr_block    = var.opsvpn_peering.cidr
  vpc_peering_connection_id = var.opsvpn_peering.create ? aws_vpc_peering_connection.ops_vpn[0].id : var.opsvpn_peering.peering_id
}

## Peering to OPS FRA VPN
resource "aws_vpc_peering_connection" "ops_fra_vpn" {
  count         = var.opsfravpn_peering.create ? 1 : 0
  peer_region   = var.opsfravpn_peering.peer_region
  peer_owner_id = var.opsfravpn_peering.peer_owner
  peer_vpc_id   = var.opsfravpn_peering.peer_vpc
  vpc_id        = data.aws_vpc.selected.id
  tags = {
    Name = "ops_fra_vpn"
  }
}
resource "aws_route" "local-to-ops_fra_vpn" {
  count                     = var.redundancy
  route_table_id            = element(aws_route_table.eks_to_nat.*.id, count.index)
  destination_cidr_block    = var.opsfravpn_peering.cidr
  vpc_peering_connection_id = var.opsfravpn_peering.create ? aws_vpc_peering_connection.ops_fra_vpn[0].id : var.opsfravpn_peering.peering_id
}

##Peering to PBX Stage
resource "aws_vpc_peering_connection" "pbx" {
  count         = var.pbx_peering.create ? 1 : 0
  peer_region   = var.pbx_peering.peer_region
  peer_owner_id = var.pbx_peering.peer_owner
  peer_vpc_id   = var.pbx_peering.peer_vpc
  vpc_id        = data.aws_vpc.selected.id
  tags = {
    Name = "ops_fra_vpn"
  }
}

resource "aws_route" "local-to-pbx-stage" {
  count                     = var.pbx_peering.create || var.pbx_peering.enabled ? var.redundancy : 0
  route_table_id            = element(aws_route_table.eks_to_nat.*.id, count.index)
  destination_cidr_block    = var.pbx_peering.cidr
  vpc_peering_connection_id = var.pbx_peering.create ? aws_vpc_peering_connection.pbx[0].id : var.pbx_peering.peering_id
}