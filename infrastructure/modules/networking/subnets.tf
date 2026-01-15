// Public Subnets in different Availability Zones
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${data.aws_region.current.name}a"
  map_public_ip_on_launch = false

  tags = merge(
    var.common_tags,
    {
      Name = "${var.name_prefix}public-subnet-1",
      "kubernetes.io/role/elb" = "1",
      # "kubernetes.io/cluster/${var.name_prefix}eks" = "shared"
    }
  )
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${data.aws_region.current.name}b"
  map_public_ip_on_launch = false

  tags = merge(
    var.common_tags,
    {
      Name = "${var.name_prefix}public-subnet-2",
      "kubernetes.io/role/elb" = "1",
      # "kubernetes.io/cluster/${var.name_prefix}eks" = "shared"
    }
  )
}

// Private Subnets in different Availability Zones
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "${data.aws_region.current.name}a"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.name_prefix}private-subnet-1",
      "kubernetes.io/role/internal-elb" = "1",
      # "kubernetes.io/cluster/${var.name_prefix}eks" = "shared"
    }
  )
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "${data.aws_region.current.name}b"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.name_prefix}private-subnet-2",
      "kubernetes.io/role/internal-elb" = "1",
      # "kubernetes.io/cluster/${var.name_prefix}eks" = "shared"
    }
  )
}
