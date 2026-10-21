# ==========================================
# 1. NETWORKING (VPC, Subnet, IGW, Route)
# ==========================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-public-subnet" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project_name}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ==========================================
# 2. SECURITY GROUPS
# ==========================================

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Allow HTTP and SSH to app server"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-app-sg" }
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Allow PostgreSQL only from app server"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-db-sg" }
}

# ==========================================
# 3. EC2 INSTANCES
# ==========================================

resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = var.key_name

  tags = { Name = "${var.project_name}-app-server" }
}

resource "aws_instance" "db" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = var.key_name

  tags = { Name = "${var.project_name}-db-server" }
}

# ==========================================
# 4. EBS STORAGE
# ==========================================

resource "aws_ebs_volume" "app_data" {
  availability_zone = aws_instance.app.availability_zone
  size              = 8
  type              = "gp3"

  tags = { Name = "${var.project_name}-app-ebs" }
}

resource "aws_volume_attachment" "app_attach" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.app_data.id
  instance_id = aws_instance.app.id
}

resource "aws_ebs_volume" "db_data" {
  availability_zone = aws_instance.db.availability_zone
  size              = 8
  type              = "gp3"

  tags = { Name = "${var.project_name}-db-ebs" }
}

resource "aws_volume_attachment" "db_attach" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.db_data.id
  instance_id = aws_instance.db.id
}