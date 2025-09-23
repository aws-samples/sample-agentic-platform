########################################################
# Data Sources for Managed CloudFront Policies
########################################################

data "aws_cloudfront_cache_policy" "managed_caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "managed_caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "managed_cors_s3_origin" {
  name = "Managed-CORS-S3Origin"
}

data "aws_cloudfront_response_headers_policy" "managed_cors_with_preflight" {
  id = "5cc3b908-e619-4b99-88e5-2cf7f45965bd"
}
