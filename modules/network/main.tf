resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-igw" })
}

resource "aws_subnet" "public" {
  for_each = toset(var.availability_zones)

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, index(var.availability_zones, each.value))
  map_public_ip_on_launch = true

  tags = merge(var.tags, { Name = "${var.name}-public-${each.value}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, { Name = "${var.name}-public" })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  route_table_id = aws_route_table.public.id
  subnet_id      = each.value.id
}

# Tunnel은 태스크에서 Cloudflare로 outbound 연결을 만들므로 inbound rule이 필요 없다.
resource "aws_security_group" "task" {
  name_prefix = "${var.name}-task-"
  description = "No inbound access. Fargate reaches Cloudflare and AWS services outbound."
  vpc_id      = aws_vpc.this.id

  egress {
    description = "HTTPS and DNS egress for Cloudflare Tunnel, ECR, Secrets Manager and logs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-task" })

  lifecycle {
    create_before_destroy = true
  }
}
