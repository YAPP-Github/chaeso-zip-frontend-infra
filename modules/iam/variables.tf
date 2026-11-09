variable "name" { type = string }
variable "github_repository" { type = string }
variable "github_branch" { type = string }
variable "ecr_repository_arn" { type = string }
variable "static_bucket_arn" { type = string }
variable "secrets_manager_arns" { type = list(string) }
variable "log_group_arns" { type = list(string) }
variable "tags" { type = map(string) }
