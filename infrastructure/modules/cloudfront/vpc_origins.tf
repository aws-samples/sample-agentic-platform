########################################################
# VPC Origins for CloudFront
########################################################

resource "aws_cloudfront_vpc_origin" "alb" {
  count = length(var.vpc_origin_arns)

  vpc_origin_endpoint_config {
    name                   = "vpc-origin-${count.index}"
    arn                    = var.vpc_origin_arns[count.index]
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"  # Load balancer is private

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = merge(var.common_tags, {
    Name    = "${var.name_prefix}vpc-origin-${count.index}-${var.suffix}"
    Type    = "CloudFrontVPCOrigin"
    Comment = "VPC origin for private load balancer"
  })
}
