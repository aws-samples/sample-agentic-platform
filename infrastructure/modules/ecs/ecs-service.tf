# ECS Task Definition and Service

resource "aws_ecs_task_definition" "litellm" {
  family                   = "${var.name_prefix}${local.service_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    # Init container to set up database
    {
      name      = "db-init"
      image     = "postgres:16-alpine"
      essential = false
      
      environment = [
        {
          name  = "PGHOST"
          value = var.postgres_cluster_endpoint
        },
        {
          name  = "PGPORT"
          value = "5432"
        },
        {
          name  = "PGUSER"
          value = "postgres"
        },
        {
          name  = "PGDATABASE"
          value = "postgres"
        }
      ]

      secrets = [
        {
          name      = "PGPASSWORD"
          valueFrom = "${var.postgres_secret_arn}:password::"
        },
        {
          name      = "LITELLM_DB_PASSWORD"
          valueFrom = "${var.litellm_secret_arn}:POSTGRES_PASSWORD::"
        }
      ]

      command = [
        "sh", "-c", 
        "echo 'Setting up LiteLLM database...' && psql -c \"CREATE DATABASE litellm_db;\" || echo 'Database already exists' && psql -c \"CREATE USER litellm WITH PASSWORD '$LITELLM_DB_PASSWORD';\" || echo 'User already exists' && psql -c \"GRANT ALL PRIVILEGES ON DATABASE litellm_db TO litellm;\" && psql -d litellm_db -c \"GRANT ALL ON SCHEMA public TO litellm;\" && psql -d litellm_db -c \"GRANT ALL ON ALL TABLES IN SCHEMA public TO litellm;\" && psql -d litellm_db -c \"GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO litellm;\" && psql -d litellm_db -c \"ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO litellm;\" && psql -d litellm_db -c \"ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO litellm;\" && echo 'Database setup complete'"
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.litellm.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "init"
        }
      }
    },
    # Main LiteLLM container
    {
      name  = local.service_name
      image = "ghcr.io/berriai/litellm:main-latest"
      
      dependsOn = [
        {
          containerName = "db-init"
          condition     = "SUCCESS"
        }
      ]
      
      portMappings = [
        {
          containerPort = local.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "PORT"
          value = tostring(local.container_port)
        },
        {
          name  = "LITELLM_LOG_LEVEL"
          value = "INFO"
        },
        {
          name  = "AWS_DEFAULT_REGION"
          value = data.aws_region.current.name
        },
        {
          name  = "LITELLM_CACHE"
          value = "True"
        },
        {
          name  = "LITELLM_CACHE_TYPE"
          value = "redis"
        },
        {
          name  = "LITELLM_SET_VERBOSE"
          value = "True"
        },
        {
          name  = "LITELLM_HEALTH_CHECK"
          value = "True"
        },
        {
          name  = "LITELLM_MAX_BUDGET"
          value = "100"
        },
        {
          name  = "LITELLM_BUDGET_DURATION"
          value = "1h"
        },
        {
          name  = "LITELLM_CONFIG_BUCKET_NAME"
          value = aws_s3_bucket.litellm_config.id
        },
        {
          name  = "LITELLM_CONFIG_BUCKET_OBJECT_KEY"
          value = aws_s3_object.litellm_config.key
        },
        {
          name = "SERVER_ROOT_PATH"
          value = "/api/litellm"
        }
      ]

      secrets = [
        {
          name      = "LITELLM_MASTER_KEY"
          valueFrom = "${var.litellm_secret_arn}:LITELLM_MASTER_KEY::"
        },
        {
          name      = "DATABASE_URL"
          valueFrom = "${var.litellm_secret_arn}:DATABASE_URL::"
        },
        {
          name      = "REDIS_HOST"
          valueFrom = "${var.litellm_secret_arn}:REDIS_HOST::"
        },
        {
          name      = "REDIS_PORT"
          valueFrom = "${var.litellm_secret_arn}:REDIS_PORT::"
        },
        {
          name      = "REDIS_PASSWORD"
          valueFrom = "${var.litellm_secret_arn}:REDIS_PASSWORD::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.litellm.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command = [
          "CMD-SHELL",
          "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:${local.container_port}${local.health_check_path}')\" || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      essential = true
    }
  ])

  tags = var.common_tags
}

resource "aws_ecs_service" "litellm" {
  name            = "${var.name_prefix}${local.service_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.litellm.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks.id]
    subnets          = var.private_subnet_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.litellm.arn
    container_name   = local.service_name
    container_port   = local.container_port
  }

  depends_on = [aws_lb_listener.litellm]

  tags = var.common_tags

  lifecycle {
    ignore_changes = [desired_count]
  }
}
