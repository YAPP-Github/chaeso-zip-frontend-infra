variable "name" { type = string }

variable "static_domain" {
  type     = string
  default  = null
  nullable = true
}

variable "static_acm_certificate_arn" {
  type     = string
  default  = null
  nullable = true
}

variable "tags" { type = map(string) }
