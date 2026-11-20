variable "name" { type = string }
variable "github_repository" { type = string }
variable "github_branch" { type = string }
variable "ecr_repository_arn" { type = string }
variable "static_bucket_arn" { type = string }
variable "secrets_manager_arns" { type = list(string) }
variable "ecs_service_arn" { type = string }
variable "tags" { type = map(string) }
