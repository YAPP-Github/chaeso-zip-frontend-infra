variable "name" { type = string }
variable "tags" { type = map(string) }
variable "enable_image_expiration" {
  type    = bool
  default = false
}
