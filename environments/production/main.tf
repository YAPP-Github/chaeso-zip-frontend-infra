locals {
  name = "chaeso-zip-frontend"

  tags = {
    Application = "chaeso-zip-frontend"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

module "network" {
  source = "../../modules/network"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  tags               = local.tags
}

module "registry" {
  source = "../../modules/registry"

  name                    = local.name
  enable_image_expiration = var.enable_image_expiration
  tags                    = local.tags
}

module "secrets" {
  source = "../../modules/secrets"

  name = local.name
  secret_names = toset([
    "SESSION_ENCRYPTION_KEY",
    "OBSERVABILITY_METRICS_ENABLED",
    "OBSERVABILITY_METRICS_BEARER_TOKEN",
    "GRAFANA_PROM_URL",
    "GRAFANA_PROM_USER",
    "GRAFANA_TOKEN",
    "CLOUDFLARE_TUNNEL_TOKEN",
  ])
  tags = local.tags
}

module "iam" {
  source = "../../modules/iam"

  name                 = local.name
  github_repository    = var.github_repository
  github_branch        = var.github_branch
  ecr_repository_arn   = module.registry.repository_arn
  static_bucket_arn    = module.delivery.bucket_arn
  secrets_manager_arns = values(module.secrets.arns)
  ecs_service_arn      = "arn:aws:ecs:${var.aws_region}:${var.aws_account_id}:service/${local.name}/${local.name}"
  tags                 = local.tags
}

module "delivery" {
  source = "../../modules/delivery"

  name                       = local.name
  static_domain              = var.static_domain
  static_acm_certificate_arn = var.static_acm_certificate_arn
  tags                       = local.tags
}

module "ecs" {
  source = "../../modules/ecs"
  # Role ARN references alone do not wait for permission attachments.
  depends_on = [module.iam]

  name                   = local.name
  aws_region             = var.aws_region
  subnet_ids             = module.network.public_subnet_ids
  security_group_id      = module.network.task_security_group_id
  execution_role_arn     = module.iam.execution_role_arn
  task_role_arn          = module.iam.task_role_arn
  app_image              = var.app_image
  alloy_image            = var.alloy_image
  cloudflared_image      = var.cloudflared_image
  secret_arns            = module.secrets.arns
  desired_count          = var.desired_count
  task_cpu               = var.task_cpu
  task_memory            = var.task_memory
  bff_allowed_origins    = var.bff_allowed_origins
  enable_execute_command = var.enable_execute_command
  tags                   = local.tags
}
