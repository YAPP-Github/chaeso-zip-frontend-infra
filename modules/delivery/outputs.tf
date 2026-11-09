output "bucket_name" { value = aws_s3_bucket.static.bucket }
output "bucket_arn" { value = aws_s3_bucket.static.arn }
output "distribution_id" { value = aws_cloudfront_distribution.static.id }
output "distribution_domain" { value = aws_cloudfront_distribution.static.domain_name }
