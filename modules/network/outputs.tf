output "public_subnet_ids" { value = [for subnet in aws_subnet.public : subnet.id] }
output "task_security_group_id" { value = aws_security_group.task.id }
