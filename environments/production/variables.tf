variable "aws_account_id" {
  type        = string
  description = "Target AWS account ID. Kept outside version control."
}

variable "aws_region" {
  type        = string
  description = "Production workload region. Seoul is selected to minimize latency for Korean users."
  default     = "ap-northeast-2"
}

variable "availability_zones" {
  type    = list(string)
  default = ["ap-northeast-2a", "ap-northeast-2b"]
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "github_repository" {
  type    = string
  default = "YAPP-Github/28th-Web-Team-4-FE"
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "app_image" {
  type        = string
  description = "Immutable ECR image URI. Push it before applying the ECS service."
}

variable "alloy_image" {
  type        = string
  description = "Immutable ECR image URI for Alloy."
}

variable "cloudflared_image" {
  type        = string
  description = "ARM64-compatible cloudflared image, pinned to a verified tag or digest before production apply."
}

variable "desired_count" {
  type        = number
  default     = 0
  description = "Keep 0 during bootstrap; reviewed steady-state target is 1 after secrets, images and Tunnel are ready."
}

variable "enable_image_expiration" {
  type        = bool
  default     = false
  description = "Count policies cannot protect live/rollback digests. Keep disabled until a safe cleanup process is reviewed."
}

variable "task_cpu" {
  type    = number
  default = 256
}

variable "task_memory" {
  type    = number
  default = 1024
}

variable "bff_allowed_origins" {
  type    = string
  default = "https://chaeso-zip.com,http://localhost:3000"
}

variable "enable_execute_command" {
  type    = bool
  default = false
}

variable "static_domain" {
  type        = string
  default     = null
  nullable    = true
  description = "Set only after ACM validation is complete."
}

variable "static_acm_certificate_arn" {
  type        = string
  default     = null
  nullable    = true
  description = "us-east-1 ACM certificate ARN for the static CloudFront hostname."
}
