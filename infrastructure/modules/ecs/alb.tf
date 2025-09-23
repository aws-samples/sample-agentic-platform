# Application Load Balancer

resource "aws_lb" "main" {
  # checkov:skip=CKV_AWS_91: Access logging is optional for this sample
  # checkov:skip=CKV_AWS_92: Deletion protection is disabled for easier cleanup
  # checkov:skip=CKV2_AWS_28: WAF is optional for this sample
  # checkov:skip=CKV_AWS_150: Deletion protection is disabled for easier cleanup
  # checkov:skip=CKV_AWS_131: alb intentionally http only and internal. Exposing it through vpc origin to enforce https at the publically exposed endpoint. 
  # checkov:skip=CKV_AWS_2: alb intentionally http only and internal. Exposing it through vpc origin to enforce https at the publically exposed endpoint. 
  # checkov:skip=CKV2_AWS_20: alb intentionally http only and internal. Exposing it through vpc origin to enforce https at the publically exposed endpoint. 
  name               = "${var.name_prefix}${local.service_name}-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.private_subnet_ids

  enable_deletion_protection = false

  tags = var.common_tags
}

resource "aws_lb_target_group" "litellm" {
  # checkov:skip=CKV_AWS_378: ALB is internal and only accessable through Cloudfront with https. Internal comms are http to avoid hard requirement on a cert.
  name        = "${var.name_prefix}${local.service_name}-tg"
  port        = local.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = local.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = var.common_tags
}

resource "aws_lb_listener" "litellm" {
  # checkov:skip=CKV_AWS_2: ALB is internal and only accessable through Cloudfront with https. Internal comms are http to avoid hard requirement on a cert.
  # checkov:skip=CKV_AWS_103: TLS not relevant because internal comms are http while external is https through cloudfront.
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.litellm.arn
  }

  tags = var.common_tags
}
