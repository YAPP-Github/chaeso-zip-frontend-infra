resource "aws_secretsmanager_secret" "this" {
  for_each = var.secret_names

  name                    = "/${var.name}/production/${each.value}"
  recovery_window_in_days = 7

  tags = var.tags
}
