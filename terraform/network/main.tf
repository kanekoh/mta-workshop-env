# VPC
resource "aws_vpc" "rosa_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-vpc"
    }
  )
}

# Internet Gateway
resource "aws_internet_gateway" "rosa_igw" {
  vpc_id = aws_vpc.rosa_vpc.id

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-igw"
    }
  )
}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Public Subnet
resource "aws_subnet" "rosa_public_subnet" {
  count                   = var.availability_zone_count
  vpc_id                  = aws_vpc.rosa_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-public-subnet-${count.index + 1}"
    }
  )
}

# Private Subnet
resource "aws_subnet" "rosa_private_subnet" {
  count             = var.availability_zone_count
  vpc_id            = aws_vpc.rosa_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 128)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-private-subnet-${count.index + 1}"
    }
  )
}

# Elastic IP for NAT Gateway
resource "aws_eip" "rosa_nat_eip" {
  count  = var.availability_zone_count
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-nat-eip-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.rosa_igw]
}

# NAT Gateway
resource "aws_nat_gateway" "rosa_nat_gw" {
  count         = var.availability_zone_count
  allocation_id = aws_eip.rosa_nat_eip[count.index].id
  subnet_id     = aws_subnet.rosa_public_subnet[count.index].id

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-nat-gw-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.rosa_igw]
}

# Public Route Table
resource "aws_route_table" "rosa_public_rt" {
  vpc_id = aws_vpc.rosa_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.rosa_igw.id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-public-rt"
    }
  )
}

# Private Route Table
resource "aws_route_table" "rosa_private_rt" {
  count  = var.availability_zone_count
  vpc_id = aws_vpc.rosa_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.rosa_nat_gw[count.index].id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-private-rt-${count.index + 1}"
    }
  )
}

# Route Table Associations
resource "aws_route_table_association" "rosa_public_rta" {
  count          = var.availability_zone_count
  subnet_id      = aws_subnet.rosa_public_subnet[count.index].id
  route_table_id = aws_route_table.rosa_public_rt.id
}

resource "aws_route_table_association" "rosa_private_rta" {
  count          = var.availability_zone_count
  subnet_id      = aws_subnet.rosa_private_subnet[count.index].id
  route_table_id = aws_route_table.rosa_private_rt[count.index].id
}

