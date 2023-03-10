terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "ap-southeast-1"
}

# setup VPC and networking
resource "aws_default_vpc" "nginx-vpc-086" {
  tags = {
    env = "development"
  }
}

resource "aws_internet_gateway" "main" {
  # vpc_id = aws_default_vpc.nginx-vpc-086.id
}

resource "aws_default_subnet" "nginx-subnet-private" {
  availability_zone       = "ap-southeast-1a"
  map_public_ip_on_launch = true
  tags = {
    env = "development"
  }
}

resource "aws_default_subnet" "nginx-subnet-public" {
  availability_zone       = "ap-southeast-1b"
  map_public_ip_on_launch = true
  tags = {
    env = "development"
  }
}

resource "aws_security_group" "nginx-explore" {
  name        = "allow_http"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_default_vpc.nginx-vpc-086.id

  ingress {
    description = "Allow HTTP for all"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Allow egress for all"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# load balancer
resource "aws_lb" "nginx-lb" {
  name               = "nginx-alb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.nginx-explore.id]
  subnets            = [aws_default_subnet.nginx-subnet-public.id, aws_default_subnet.nginx-subnet-private.id]

  tags = {
    env = "development"
  }
}

resource "aws_lb_target_group" "nginx-lb" {
  name        = "tf-nginx-lb-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_default_vpc.nginx-vpc-086.id
}

resource "aws_lb_listener" "nginx-alb-listener" {
  load_balancer_arn = aws_lb.nginx-lb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx-lb.arn
  }
}

# setup ECS cluster and task
resource "aws_ecs_cluster" "nginx" {
  name = "nginx-cluster"
}

resource "aws_ecs_cluster_capacity_providers" "nginx" {
  cluster_name       = aws_ecs_cluster.nginx.name
  capacity_providers = ["FARGATE"]
}

resource "aws_ecs_task_definition" "nginx" {
  family                   = "service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  container_definitions = jsonencode([{
    name      = "nginx-server"
    image     = "nginx"
    essential = true

    portMappings = [{
      containerPort = 80
      hostPort      = 80
    }]
  }])
}

resource "aws_ecs_service" "nginx" {
  name            = "nginx-service"
  cluster         = aws_ecs_cluster.nginx.id
  task_definition = aws_ecs_task_definition.nginx.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_default_subnet.nginx-subnet-public.id, aws_default_subnet.nginx-subnet-private.id]
    security_groups  = [aws_security_group.nginx-explore.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.nginx-lb.arn
    container_name   = "nginx-server"
    container_port   = 80
  }

  depends_on = [aws_internet_gateway.main]

  tags = {
    env = "development"
  }
}
