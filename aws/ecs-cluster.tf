terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = "qualys-registry-cluster"
}

variable "instance_type" {
  description = "EC2 instance type for ECS cluster nodes"
  type        = string
  default     = "t3.medium"
}

variable "min_size" {
  description = "Minimum number of EC2 instances"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of EC2 instances"
  type        = number
  default     = 3
}

variable "desired_capacity" {
  description = "Desired number of EC2 instances"
  type        = number
  default     = 2
}

variable "create_vpc" {
  description = "Create new VPC with private subnets and NAT gateway"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "Existing VPC ID (required if create_vpc=false)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Existing subnet IDs (required if create_vpc=false)"
  type        = list(string)
  default     = []
}

variable "key_name" {
  description = "EC2 Key Pair for SSH access"
  type        = string
  default     = ""
}

variable "qualys_image" {
  description = "Qualys container sensor image from private ECR"
  type        = string
}

variable "qualys_activation_id" {
  description = "Qualys activation ID"
  type        = string
  sensitive   = true
}

variable "qualys_customer_id" {
  description = "Qualys customer ID"
  type        = string
  sensitive   = true
}

variable "qualys_pod_url" {
  description = "Qualys Container Security Server URL"
  type        = string
  default     = ""
}

variable "qualys_https_proxy" {
  description = "HTTPS proxy server (FQDN or IP:port)"
  type        = string
  default     = ""
}

variable "https_proxy" {
  description = "Standard HTTPS proxy environment variable"
  type        = string
  default     = ""
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

data "aws_caller_identity" "current" {}

resource "aws_vpc" "main" {
  count                = var.create_vpc ? 1 : 0
  cidr_block           = "172.20.250.0/24"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = var.create_vpc ? 2 : 0
  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = cidrsubnet("172.20.250.0/24", 2, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-public-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = var.create_vpc ? 2 : 0
  vpc_id            = aws_vpc.main[0].id
  cidr_block        = cidrsubnet("172.20.250.0/24", 2, count.index + 2)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.cluster_name}-private-${count.index + 1}"
  }
}

resource "aws_eip" "nat" {
  count  = var.create_vpc ? 2 : 0
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nat-eip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "main" {
  count         = var.create_vpc ? 2 : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.cluster_name}-nat-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = var.create_vpc ? 2 : 0
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table" "private" {
  count  = var.create_vpc ? 2 : 0
  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt-${count.index + 1}"
  }
}

resource "aws_route_table_association" "private" {
  count          = var.create_vpc ? 2 : 0
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_security_group" "ecs_instances" {
  name        = "QualysRegistrySensorECS-SG"
  description = "Security group for Qualys Registry Sensor ECS instances"
  vpc_id      = var.create_vpc ? aws_vpc.main[0].id : var.vpc_id

  egress {
    description = "HTTPS to internet for Qualys platform and ECR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS queries"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "QualysRegistrySensorECS-SG"
  }
}

resource "aws_kms_key" "logs" {
  description             = "KMS key for CloudWatch Logs encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-logs-key"
  }
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${var.cluster_name}-logs"
  target_key_id = aws_kms_key.logs.key_id
}

resource "aws_kms_key" "secrets" {
  description             = "KMS key for Secrets Manager encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.cluster_name}-secrets-key"
  }
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.cluster_name}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

resource "aws_secretsmanager_secret" "qualys_activation_id" {
  name                    = "${var.cluster_name}/qualys/activation-id"
  description             = "Qualys activation ID"
  recovery_window_in_days = 7
  kms_key_id              = aws_kms_key.secrets.arn

  tags = {
    Name = "${var.cluster_name}-qualys-activation-id"
  }
}

resource "aws_secretsmanager_secret_version" "qualys_activation_id" {
  secret_id     = aws_secretsmanager_secret.qualys_activation_id.id
  secret_string = var.qualys_activation_id
}

resource "aws_secretsmanager_secret" "qualys_customer_id" {
  name                    = "${var.cluster_name}/qualys/customer-id"
  description             = "Qualys customer ID"
  recovery_window_in_days = 7
  kms_key_id              = aws_kms_key.secrets.arn

  tags = {
    Name = "${var.cluster_name}-qualys-customer-id"
  }
}

resource "aws_secretsmanager_secret_version" "qualys_customer_id" {
  secret_id     = aws_secretsmanager_secret.qualys_customer_id.id
  secret_string = var.qualys_customer_id
}

resource "aws_cloudwatch_log_group" "qualys" {
  name              = "/ecs/${var.cluster_name}/qualys-sensor"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.logs.arn
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count             = var.create_vpc ? 1 : 0
  name              = "/vpc/${var.cluster_name}/flow-logs"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.logs.arn
}

resource "aws_iam_role" "flow_logs" {
  count = var.create_vpc ? 1 : 0
  name  = "${var.cluster_name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.create_vpc ? 1 : 0
  name  = "flow-logs-policy"
  role  = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "main" {
  count                = var.create_vpc ? 1 : 0
  vpc_id               = aws_vpc.main[0].id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn         = aws_iam_role.flow_logs[0].arn

  tags = {
    Name = "${var.cluster_name}-flow-logs"
  }
}

resource "aws_ecs_cluster" "main" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = var.cluster_name
  }
}

resource "aws_iam_role" "ecs_instance" {
  name = "QualysRegistrySensorECSInstanceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "QualysRegistrySensorECSInstanceProfile"
  role = aws_iam_role.ecs_instance.name
}

resource "aws_iam_role" "ecs_task_execution" {
  name = "QualysRegistrySensorTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "secrets-access"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.qualys_activation_id.arn,
          aws_secretsmanager_secret.qualys_customer_id.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = [
          aws_kms_key.secrets.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task" {
  name = "QualysRegistrySensorTaskRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_launch_template" "ecs" {
  name_prefix   = "${var.cluster_name}-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance.name
  }

  vpc_security_group_ids = [aws_security_group.ecs_instances.id]
  key_name               = var.key_name != "" ? var.key_name : null

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      encrypted             = true
      volume_type           = "gp3"
      volume_size           = 30
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-ecs-instance"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${var.cluster_name}-ecs-volume"
    }
  }
}

resource "aws_autoscaling_group" "ecs" {
  name                = "${var.cluster_name}-asg"
  vpc_zone_identifier = var.create_vpc ? aws_subnet.private[*].id : var.subnet_ids
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-ecs-instance"
    propagate_at_launch = true
  }
}

locals {
  container_environment = concat(
    var.qualys_pod_url != "" ? [{ name = "POD_URL", value = var.qualys_pod_url }] : [],
    var.qualys_https_proxy != "" ? [{ name = "qualys_https_proxy", value = var.qualys_https_proxy }] : [],
    var.https_proxy != "" ? [{ name = "https_proxy", value = var.https_proxy }] : []
  )

  container_secrets = [
    {
      name      = "ACTIVATIONID"
      valueFrom = aws_secretsmanager_secret.qualys_activation_id.arn
    },
    {
      name      = "CUSTOMERID"
      valueFrom = aws_secretsmanager_secret.qualys_customer_id.arn
    }
  ]
}

resource "aws_ecs_task_definition" "qualys" {
  family                   = "${var.cluster_name}-qualys-sensor"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name        = "qualys-container-sensor"
      image       = var.qualys_image
      essential   = true
      privileged  = true
      environment = local.container_environment
      secrets     = local.container_secrets
      mountPoints = [
        {
          sourceVolume  = "docker-sock"
          containerPath = "/var/run/docker.sock"
          readOnly      = false
        },
        {
          sourceVolume  = "persistent-volume"
          containerPath = "/usr/local/qualys/qpa/data/cert"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.qualys.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "qualys"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "pgrep -f qualys || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  volume {
    name      = "docker-sock"
    host_path = "/var/run/docker.sock"
  }

  volume {
    name      = "persistent-volume"
    host_path = "/var/qualys/qpa/data/cert"
  }
}

resource "aws_ecs_service" "qualys" {
  name            = "${var.cluster_name}-qualys-sensor"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.qualys.arn
  desired_count   = var.desired_capacity

  placement_constraints {
    type = "distinctInstance"
  }

  scheduling_strategy = "REPLICA"

  depends_on = [aws_autoscaling_group.ecs]
}

output "cluster_name" {
  value       = aws_ecs_cluster.main.name
  description = "ECS cluster name"
}

output "cluster_arn" {
  value       = aws_ecs_cluster.main.arn
  description = "ECS cluster ARN"
}

output "vpc_id" {
  value       = var.create_vpc ? aws_vpc.main[0].id : var.vpc_id
  description = "VPC ID"
}

output "private_subnet_ids" {
  value       = var.create_vpc ? aws_subnet.private[*].id : var.subnet_ids
  description = "Private subnet IDs"
}

output "task_definition_arn" {
  value       = aws_ecs_task_definition.qualys.arn
  description = "Qualys task definition ARN"
}

output "service_name" {
  value       = aws_ecs_service.qualys.name
  description = "ECS service name"
}

output "secrets_manager_arns" {
  value = {
    activation_id = aws_secretsmanager_secret.qualys_activation_id.arn
    customer_id   = aws_secretsmanager_secret.qualys_customer_id.arn
  }
  description = "Secrets Manager ARNs for Qualys credentials"
}
