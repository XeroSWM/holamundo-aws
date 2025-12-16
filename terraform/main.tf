terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# =========================================================
# DATA SOURCES
# =========================================================

data "aws_vpc" "default" {
  default = true
}

# SOLO AZ SOPORTADAS (evita error t3.micro)
data "aws_subnets" "filtered" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name = "availability-zone"
    values = [
      "us-east-1a",
      "us-east-1b",
      "us-east-1c",
      "us-east-1d",
      "us-east-1f"
    ]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# =========================================================
# SECURITY GROUP
# =========================================================

resource "aws_security_group" "web_sg" {
  name   = "holamundo-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
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

# =========================================================
# APPLICATION LOAD BALANCER
# =========================================================

resource "aws_lb" "alb" {
  name               = "holamundo-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = data.aws_subnets.filtered.ids
}

resource "aws_lb_target_group" "tg" {
  name     = "holamundo-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 15
    timeout             = 5
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# =========================================================
# LAUNCH TEMPLATE (EC2 + NGINX + DOCKER)
# =========================================================

resource "aws_launch_template" "lt" {
  name_prefix   = "holamundo-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_sg.id]
  }

  user_data = base64encode(<<EOF
#!/bin/bash
dnf update -y

# Instalar Docker, Git y NGINX
dnf install -y docker git nginx

systemctl enable docker
systemctl start docker

systemctl enable nginx
systemctl start nginx

usermod -aG docker ec2-user

# Docker Compose
curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
-o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# NGINX COMO REVERSE PROXY A FLASK
cat <<NGINX > /etc/nginx/conf.d/app.conf
server {
  listen 80;
  location / {
    proxy_pass http://127.0.0.1:5000;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
  }
}
NGINX

rm -f /etc/nginx/conf.d/default.conf
systemctl restart nginx

# CLONAR APP Y LEVANTAR DOCKER
cd /home/ec2-user
git clone https://github.com/XeroSWM/holamundo-aws.git
cd holamundo-aws
docker-compose up --build -d
EOF
  )
}

# =========================================================
# AUTO SCALING GROUP
# =========================================================

resource "aws_autoscaling_group" "asg" {
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = data.aws_subnets.filtered.ids
  target_group_arns   = [aws_lb_target_group.tg.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "holamundo-ec2"
    propagate_at_launch = true
  }
}

# =========================================================
# OUTPUTS
# =========================================================

output "alb_dns" {
  description = "DNS público del ALB"
  value       = aws_lb.alb.dns_name
}

output "app_url" {
  description = "URL pública de la aplicación"
  value       = "http://${aws_lb.alb.dns_name}"
}

output "public_port" {
  value = 80
}

output "internal_app_port" {
  value = 5000
}

output "internal_db_port" {
  value = 3306
}

output "architecture" {
  value = "ALB (80) → EC2 → NGINX → Docker → Flask (5000) → MySQL (3306)"
}
