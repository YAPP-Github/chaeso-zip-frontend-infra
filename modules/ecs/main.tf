locals {
  log_group_name = "/ecs/${var.name}"

  container_definitions = [
    {
      name              = "nextjs"
      image             = var.app_image
      essential         = true
      cpu               = 160
      memoryReservation = 384
      portMappings = [{
        containerPort = 3000
        hostPort      = 3000
        protocol      = "tcp"
        appProtocol   = "http"
      }]
      environment = [
        { name = "HOSTNAME", value = "0.0.0.0" },
        { name = "BFF_ALLOWED_ORIGINS", value = var.bff_allowed_origins },
      ]
      secrets = [
        { name = "SESSION_ENCRYPTION_KEY", valueFrom = var.secret_arns["SESSION_ENCRYPTION_KEY"] },
        { name = "OBSERVABILITY_METRICS_ENABLED", valueFrom = var.secret_arns["OBSERVABILITY_METRICS_ENABLED"] },
        { name = "OBSERVABILITY_METRICS_BEARER_TOKEN", valueFrom = var.secret_arns["OBSERVABILITY_METRICS_BEARER_TOKEN"] },
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://127.0.0.1:3000/api/internal/health >/dev/null || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = local.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "nextjs"
          mode                  = "non-blocking"
          max-buffer-size       = "1m"
        }
      }
    },
    {
      name              = "alloy"
      image             = var.alloy_image
      essential         = false
      cpu               = 48
      memoryReservation = 128
      memory            = 256
      environment       = [{ name = "GOMEMLIMIT", value = "192MiB" }]
      restartPolicy = {
        enabled              = true
        restartAttemptPeriod = 60
      }
      secrets = [
        { name = "GRAFANA_PROM_URL", valueFrom = var.secret_arns["GRAFANA_PROM_URL"] },
        { name = "GRAFANA_PROM_USER", valueFrom = var.secret_arns["GRAFANA_PROM_USER"] },
        { name = "GRAFANA_TOKEN", valueFrom = var.secret_arns["GRAFANA_TOKEN"] },
        { name = "OBSERVABILITY_METRICS_BEARER_TOKEN", valueFrom = var.secret_arns["OBSERVABILITY_METRICS_BEARER_TOKEN"] },
      ]
      dependsOn = [{ containerName = "nextjs", condition = "HEALTHY" }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = local.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "alloy"
          mode                  = "non-blocking"
          max-buffer-size       = "1m"
        }
      }
    },
    {
      name              = "cloudflared"
      image             = var.cloudflared_image
      essential         = true
      cpu               = 48
      memoryReservation = 128
      command           = ["tunnel", "--no-autoupdate", "--loglevel", "info", "--metrics", "0.0.0.0:2000", "run"]
      secrets           = [{ name = "TUNNEL_TOKEN", valueFrom = var.secret_arns["CLOUDFLARE_TUNNEL_TOKEN"] }]
      dependsOn         = [{ containerName = "nextjs", condition = "HEALTHY" }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = local.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "cloudflared"
          mode                  = "non-blocking"
          max-buffer-size       = "1m"
        }
      }
    },
  ]
}

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = var.tags
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  container_definitions    = jsonencode(local.container_definitions)

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE_SPOT"]
}

resource "aws_ecs_service" "this" {
  depends_on = [aws_ecs_cluster_capacity_providers.this, aws_cloudwatch_log_group.this]

  name            = var.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_execute_command             = var.enable_execute_command

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    assign_public_ip = true
    security_groups  = [var.security_group_id]
    subnets          = var.subnet_ids
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  lifecycle {
    # App repository CD owns image tag/task-definition revisions after infrastructure bootstrap.
    ignore_changes = [task_definition]
  }

  tags = var.tags
}
