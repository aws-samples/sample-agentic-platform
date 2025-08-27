# Security Groups

# Security group for ECS tasks
resource "aws_security_group" "ecs_tasks" {
  # checkov:skip=CKV_AWS_382: output traffic allowed intentionall. Ingress is locked down.
  name_prefix = "${var.name_prefix}ecs-tasks-"
  description = "Security group for ECS tasks"
  vpc_id      = var.vpc_id

  # Allow inbound traffic from ALB
  ingress {
    description     = "HTTP from ALB"
    from_port       = local.container_port
    to_port         = local.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}ecs-tasks-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for Application Load Balancer
resource "aws_security_group" "alb" {
  # checkov:skip=CKV_AWS_382: output traffic allowed intentional.
  # checkov:skip=CKV_AWS_260: ALB is internal and accessable as a VPC origin from Cloudfront for https. 
  name_prefix = "${var.name_prefix}alb-"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  # Allow inbound HTTP traffic
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound HTTPS traffic
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}alb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}
