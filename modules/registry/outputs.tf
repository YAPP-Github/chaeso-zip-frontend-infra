output "repository_arn" { value = aws_ecr_repository.this.arn }
output "repository_url" { value = aws_ecr_repository.this.repository_url }
output "expiration_policy_preview" { value = local.expiration_policy }
