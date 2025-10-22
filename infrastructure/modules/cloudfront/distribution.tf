########################################################
# CloudFront Distribution
########################################################

resource "aws_cloudfront_distribution" "spa_website" {
  # checkov:skip=CKV2_AWS_42:Using CloudFront default certificate for sample application - custom SSL cert not required
  # checkov:skip=CKV_AWS_310:Origin failover not required for example S3 origin static website
  # checkov:skip=CKV_AWS_374:Geo restriction not required for example application - global access intended
  # checkov:skip=CKV_AWS_68:WAF intentionally disabled - regional stacks fail to deploy because WAF is global and requires us-east-1
  # checkov:skip=CKV2_AWS_47:WAF intentionally disabled - regional stacks fail to deploy because WAF is global and requires us-east-1
  # checkov:skip=CKV_AWS_130:CloudFront access logging disabled. This is a sample website / app.
  # checkov:skip=CKV_AWS_86:Removing access logging

  # Logging disabled for security and cost optimization

  # S3 origin for static website
  origin {
    domain_name              = var.s3_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.spa_website.id
    origin_id                = "S3-${var.s3_bucket_name}"

    # Add origin shield for better performance and cost optimization
    origin_shield {
      enabled              = true
      origin_shield_region = "us-west-2"
    }
  }

  # VPC origins for private load balancers
  dynamic "origin" {
    for_each = aws_cloudfront_vpc_origin.alb
    content {
      domain_name = var.load_balancer_dns_name
      origin_id   = "VPC-${origin.key}"
      
      vpc_origin_config {
        vpc_origin_id = origin.value.id
      }
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for SPA website - ${var.environment}"
  default_root_object = "index.html"
  

  # Cache behavior for the default path
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${var.s3_bucket_name}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy     = "redirect-to-https"
    min_ttl                    = 0
    default_ttl                = 3600
    max_ttl                    = 86400
    compress                   = true
    response_headers_policy_id = aws_cloudfront_response_headers_policy.spa_website.id
  }

  # Cache behavior for API paths (/api/*)
  dynamic "ordered_cache_behavior" {
    for_each = length(var.vpc_origin_arns) > 0 ? [1] : []
    content {
      path_pattern     = "/api/*"
      allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "VPC-0"  # Use first VPC origin

      cache_policy_id            = data.aws_cloudfront_cache_policy.managed_caching_disabled.id
      response_headers_policy_id = data.aws_cloudfront_response_headers_policy.managed_cors_with_preflight.id

      viewer_protocol_policy = "redirect-to-https"
      compress              = false
    }
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}spa-website-cf-${var.suffix}"
    Type = "CloudFrontDistribution"
  })

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  # Custom error responses for SPA routing
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }
}
