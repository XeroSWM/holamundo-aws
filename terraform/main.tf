############################################
# TERRAFORM BACKEND + PROVIDER
############################################

terraform {
  backend "s3" {
    bucket         = "tf-holamundo-state-123456"
    key            = "infra/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"
}

############################################
# DATA SOURCES
############################################

data "aws_availability_zones" "available" {}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

############################################
# NETWORKING (VPC)
############################################

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet("10.0.0.0/16", 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

############################################
# SECURITY GROUPS
############################################

resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

############################################
# APPLICATION LOAD BALANCER
############################################

resource "aws_lb" "app_lb" {
  name               = "holamundo-alb"
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb_sg.id]
}

resource "aws_lb_target_group" "app_tg" {
  name     = "holamundo-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

############################################
# LAUNCH TEMPLATE + USER DATA
############################################

resource "aws_launch_template" "app" {
  name_prefix   = "holamundo-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = base64encode(<<EOF
#!/bin/bash
yum update -y
yum install docker -y
service docker start
usermod -aG docker ec2-user

curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

mkdir /app
cat <<'EOT' > /app/docker-compose.yml
version: '3'
services:
  db:
    image: mysql:8
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: holamundo

  app:
    image: nginx
    ports:
      - "80:80"
    depends_on:
      - db
EOT

cd /app
docker-compose up -d
EOF
  )
}

############################################
# AUTO SCALING GROUP
############################################

resource "aws_autoscaling_group" "app" {
  min_size            = 4
  max_size            = 6
  desired_capacity    = 4
  vpc_zone_identifier = aws_subnet.public[*].id

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app_tg.arn]
}



############################################
# OUTPUTS (FRONTEND TERRAFORM)
############################################

# URL principal (frontend)
output "frontend_url" {
  description = "URL del Application Load Balancer"
  value       = "http://${aws_lb.app_lb.dns_name}"
}

# DNS del Load Balancer
output "alb_dns" {
  description = "DNS del ALB"
  value       = aws_lb.app_lb.dns_name
}

# Instancias EC2 creadas por el ASG
data "aws_instances" "asg_instances" {
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [aws_autoscaling_group.app.name]
  }
}

# IDs de las instancias
output "ec2_instance_ids" {
  description = "IDs de las instancias EC2 del ASG"
  value       = data.aws_instances.asg_instances.ids
}

# IPs privadas de las instancias
output "ec2_private_ips" {
  description = "IPs privadas de las instancias EC2"
  value       = data.aws_instances.asg_instances.private_ips
}
