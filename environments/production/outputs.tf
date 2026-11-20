output "ecr_repository_url" {
  value = module.registry.repository_url
}

output "github_actions_role_arn" {
  value = module.iam.github_actions_role_arn
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_service_name" {
  value = module.ecs.service_name
}

output "static_distribution_domain" {
  value = module.delivery.distribution_domain
}

output "static_bucket_name" {
  value = module.delivery.bucket_name
}

output "runtime_secret_arns" {
  value     = module.secrets.arns
  sensitive = true
}
output "image_expiration_policy_preview" {
  value = module.registry.expiration_policy_preview
}

output "initial_task_definition_arn" {
  value = module.ecs.task_definition_arn
}
