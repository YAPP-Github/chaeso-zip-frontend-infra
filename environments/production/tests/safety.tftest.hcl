mock_provider "aws" {}

run "ecs_runtime_guards" {
  command = plan
  module {
    source = "../../modules/ecs"
  }
  variables {
    name                   = "test-frontend"
    aws_region             = "ap-northeast-2"
    subnet_ids             = ["subnet-12345678", "subnet-87654321"]
    security_group_id      = "sg-12345678"
    execution_role_arn     = "arn:aws:iam::123456789012:role/execution"
    task_role_arn          = "arn:aws:iam::123456789012:role/task"
    app_image              = "example/app:test"
    alloy_image            = "example/alloy:test"
    cloudflared_image      = "example/cloudflared:test"
    desired_count          = 0
    task_cpu               = 256
    task_memory            = 1024
    bff_allowed_origins    = "https://example.com"
    enable_execute_command = false
    tags                   = {}
    secret_arns = {
      SESSION_ENCRYPTION_KEY             = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:session"
      OBSERVABILITY_METRICS_ENABLED      = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:enabled"
      OBSERVABILITY_METRICS_BEARER_TOKEN = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:metrics"
      GRAFANA_PROM_URL                   = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:url"
      GRAFANA_PROM_USER                  = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:user"
      GRAFANA_TOKEN                      = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:token"
      CLOUDFLARE_TUNNEL_TOKEN            = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:tunnel"
    }
  }
  assert {
    condition = alltrue([for container in jsondecode(aws_ecs_task_definition.this.container_definitions) :
      anytrue([for secret in container.secrets : secret.name == "OBSERVABILITY_METRICS_BEARER_TOKEN" && secret.valueFrom == var.secret_arns["OBSERVABILITY_METRICS_BEARER_TOKEN"]])
      if contains(["nextjs", "alloy"], container.name)
    ])
    error_message = "Next.js and Alloy must receive the same metrics credential reference."
  }
  assert {
    condition     = contains(aws_ecs_cluster_capacity_providers.this.capacity_providers, "FARGATE_SPOT")
    error_message = "Spot must be associated with the cluster before the service can use it."
  }
  assert {
    condition     = one([for container in jsondecode(aws_ecs_task_definition.this.container_definitions) : container.restartPolicy.enabled && container.memory == 256 if container.name == "alloy"])
    error_message = "Alloy must recover from exit and have a hard memory limit."
  }
}

run "registry_expiration_is_opt_in" {
  command = plan
  module {
    source = "../../modules/registry"
  }
  variables {
    name = "test-frontend"
    tags = {}
  }
  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == 0
    error_message = "Count-based expiration must remain disabled by default to protect running images."
  }
  assert {
    condition     = [for rule in jsondecode(output.expiration_policy_preview).rules : rule.selection.tagPrefixList[0]] == ["app-", "alloy-"]
    error_message = "Preview must count Next.js and Alloy separately."
  }
}
