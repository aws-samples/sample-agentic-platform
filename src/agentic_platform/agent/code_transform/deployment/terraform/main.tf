terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# ECR Repository
resource "aws_ecr_repository" "atx_test_runner" {
  name                 = "atx-test-runner"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "atx-test-runner"
    Environment = var.environment
    Application = "ATX-Test-Runner"
  }
}

# ECR Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "atx_test_runner" {
  repository = aws_ecr_repository.atx_test_runner.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.environment}-atx-vpc"
    Environment = var.environment
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.environment}-atx-igw"
    Environment = var.environment
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.environment}-atx-public-subnet-${count.index + 1}"
    Environment = var.environment
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.environment}-atx-public-routes"
    Environment = var.environment
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.environment}-atx-ecs-sg"
  description = "Security group for ATX Test Runner ECS tasks"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.environment}-atx-ecs-sg"
    Environment = var.environment
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "atx_test_runner" {
  name              = "/ecs/${var.environment}-atx-test-runner"
  retention_in_days = 30

  tags = {
    Name        = "${var.environment}-atx-log-group"
    Environment = var.environment
  }
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.environment}-atx-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-atx-execution-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Role for ECS Task
resource "aws_iam_role" "ecs_task" {
  name = "${var.environment}-atx-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-atx-task-role"
    Environment = var.environment
  }
}

# IAM Policy for S3 Access
resource "aws_iam_role_policy" "s3_access" {
  name = "s3-access"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.source_bucket_name}",
          "arn:aws:s3:::${var.source_bucket_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.results_bucket_name}",
          "arn:aws:s3:::${var.results_bucket_name}/*"
        ]
      }
    ]
  })
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.environment}-atx-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "${var.environment}-atx-cluster"
    Environment = var.environment
  }
}

# ECS Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 0
  }

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 4
    base              = 0
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "atx_test_runner" {
  family                   = "${var.environment}-atx-test-runner"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "atx-test-runner"
      image     = "${aws_ecr_repository.atx_test_runner.repository_url}:${var.image_version}"
      essential = true
      command = [
        "/usr/local/bin/atx-orchestrator.sh",
        "--csv-file",
        "/config/repos.csv",
        "--mode",
        "parallel",
        "--max-jobs",
        tostring(var.max_parallel_jobs)
      ]
      environment = [
        {
          name  = "AWS_DEFAULT_REGION"
          value = var.aws_region
        },
        {
          name  = "ATX_LOG_LEVEL"
          value = "INFO"
        },
        {
          name  = "SOURCE_BUCKET"
          value = var.source_bucket_name
        },
        {
          name  = "RESULTS_BUCKET"
          value = var.results_bucket_name
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.atx_test_runner.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "atx"
        }
      }
    }
  ])

  tags = {
    Name        = "${var.environment}-atx-task-definition"
    Environment = var.environment
  }
}
