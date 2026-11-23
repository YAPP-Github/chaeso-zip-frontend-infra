variable "aws_account_id" { type = string }

variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "name" {
  type    = string
  default = "chaeso-zip-frontend"
}

variable "state_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name that stores Terraform state."
}
