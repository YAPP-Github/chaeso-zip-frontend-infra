resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  # Count-based rules cannot detect running or rollback images. Enable only after preview review.
  count      = var.enable_image_expiration ? 1 : 0
  repository = aws_ecr_repository.this.name
  policy     = local.expiration_policy
}

locals {
  expiration_policy = jsonencode({
    rules = [for index, prefix in ["app-", "alloy-"] : {
      rulePriority = index + 1
      description  = "Keep the newest 10 ${prefix} images; preview before enabling"
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = [prefix]
        countType     = "imageCountMoreThan"
        countNumber   = 10
      }
      action = { type = "expire" }
    }]
  })
}
